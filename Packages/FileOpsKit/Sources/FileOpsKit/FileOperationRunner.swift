import Foundation

/// The user chose Stop at a conflict.
private struct StopRequested: Error {}

/// Runs one file operation, synchronously, on the caller's thread (a background thread in
/// the app). Records every change so the operation can be undone.
public struct FileOperationRunner: Sendable {
    /// Moves an item to the trash and returns where it went.
    public typealias Trash = @Sendable (URL) throws -> URL
    public typealias Resolve = @Sendable (Conflict) -> ConflictAnswer

    public static let systemTrash: Trash = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return (resulting as URL?) ?? url
    }

    private let trash: Trash
    private let copier: Copier

    public init(trash: @escaping Trash = FileOperationRunner.systemTrash, allowsClone: Bool = true) {
        self.trash = trash
        copier = Copier(allowsClone: allowsClone)
    }

    public func run(
        _ operation: FileOperation,
        control: OperationControl,
        progress: @escaping @Sendable (OperationProgress) -> Void,
        resolve: @escaping Resolve
    ) -> OperationResult {
        var run = Run(
            runner: self, control: control, report: progress, resolve: resolve,
            progress: OperationProgress(totalItems: operation.sources.count)
        )
        run.execute(operation)
        return run.result
    }

    enum Failure: LocalizedError {
        case intoItself(String)
        case nameTaken(String)
        case invalidName(String)

        var errorDescription: String? {
            switch self {
            case let .intoItself(name): "“\(name)” can’t be copied or moved into itself."
            case let .nameTaken(name): "The name “\(name)” is already taken."
            case let .invalidName(name): "“\(name)” is not a valid name."
            }
        }
    }

    /// State of one run.
    private struct Run {
        let runner: FileOperationRunner
        let control: OperationControl
        let report: @Sendable (OperationProgress) -> Void
        let resolve: Resolve
        var progress: OperationProgress
        var result = OperationResult()
        var decisionForAll: ConflictDecision?

        mutating func execute(_ operation: FileOperation) {
            do {
                try perform(operation)
            } catch Copier.Failure.cancelled {
                result.outcome = .cancelled
            } catch is StopRequested {
                result.outcome = .stopped
            } catch {
                result.outcome = control.isCancelled ? .cancelled : .failed(error.localizedDescription)
            }
        }

        private mutating func perform(_ operation: FileOperation) throws {
            switch operation.kind {
            case let .copy(folder):
                progress.totalBytes = Self.size(of: operation.sources)
                try place(operation.sources, into: folder, moving: false)
            case let .move(folder):
                progress.totalBytes = Self.size(of: operation.sources)
                try place(operation.sources, into: folder, moving: true)
            case .trash:
                for source in operation.sources {
                    try checkpoint()
                    try trashItem(source)
                    advance()
                }
            case let .rename(name):
                for source in operation.sources {
                    try checkpoint()
                    try rename(source, to: name)
                    advance()
                }
            case let .renameAll(names):
                try renameAll(operation.sources, to: names)
            case let .revert(changes):
                try revert(changes)
            }
        }

        /// Waits while paused; throws if cancelled.
        private func checkpoint() throws {
            guard control.proceed() else { throw Copier.Failure.cancelled }
        }

        private mutating func advance() {
            progress.completedItems += 1
            report(progress)
        }

        // MARK: - Copy and move

        private mutating func place(_ sources: [URL], into folder: URL, moving: Bool) throws {
            var completedBytes: Int64 = 0
            for source in sources {
                try checkpoint()
                let itemBytes = Self.size(of: [source])
                try place(source, into: folder, moving: moving, bytesBefore: completedBytes)
                completedBytes += itemBytes
                progress.completedBytes = completedBytes
                advance()
            }
        }

        private mutating func place(_ source: URL, into folder: URL, moving: Bool, bytesBefore: Int64) throws {
            let name = source.lastPathComponent
            let sourcePath = source.standardizedFileURL.path
            let folderPath = folder.standardizedFileURL.path
            if folderPath == sourcePath || folderPath.hasPrefix(sourcePath + "/") {
                throw Failure.intoItself(name)
            }
            let sameFolder = source.deletingLastPathComponent().standardizedFileURL.path == folderPath
            if moving, sameFolder {
                return
            }
            var destination = folder.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: destination.path) {
                // Copying into its own folder always keeps both, like Finder's Duplicate.
                let decision = sameFolder ? .keepBoth : decide(Conflict(source: source, existing: destination))
                switch decision {
                case .replace:
                    try trashItem(destination)
                case .keepBoth:
                    destination = folder.appendingPathComponent(UniqueName.make(
                        for: name,
                        avoiding: Self.names(in: folder)
                    ))
                case .skip:
                    result.skipped.append(source)
                    return
                case .stop:
                    throw StopRequested()
                }
            }
            if moving, Self.sameVolume(source, folder) {
                try FileManager.default.moveItem(at: source, to: destination)
                result.changes.append(Change(kind: .moved(from: source), url: destination))
                return
            }
            let total = progress
            let report = report
            try runner.copier.copy(source, to: destination, control: control) { copied in
                var update = total
                update.completedBytes = bytesBefore + copied
                report(update)
            }
            if moving {
                try FileManager.default.removeItem(at: source)
                result.changes.append(Change(kind: .moved(from: source), url: destination))
            } else {
                result.changes.append(Change(kind: .created, url: destination))
            }
        }

        private mutating func decide(_ conflict: Conflict) -> ConflictDecision {
            if let decisionForAll {
                return decisionForAll
            }
            let answer = resolve(conflict)
            if answer.applyToAll {
                decisionForAll = answer.decision
            }
            return answer.decision
        }

        // MARK: - Trash, rename, revert

        private mutating func trashItem(_ url: URL) throws {
            let trashed = try runner.trash(url)
            result.changes.append(Change(kind: .trashed(from: url), url: trashed))
        }

        private mutating func rename(_ source: URL, to name: String) throws {
            guard !name.isEmpty, !name.contains("/"), !name.contains(":") else { throw Failure.invalidName(name) }
            let destination = source.deletingLastPathComponent().appendingPathComponent(name)
            let onlyCase = destination.lastPathComponent.lowercased() == source.lastPathComponent.lowercased()
            if !onlyCase, FileManager.default.fileExists(atPath: destination.path) {
                throw Failure.nameTaken(name)
            }
            try FileManager.default.moveItem(at: source, to: destination)
            result.changes.append(Change(kind: .moved(from: source), url: destination))
        }

        private mutating func renameAll(_ sources: [URL], to names: [String]) throws {
            if let invalid = names.first(where: { !BatchMove.isValid($0) }) {
                throw Failure.invalidName(invalid)
            }
            try moveAll(zip(sources, names).map { source, name in
                BatchMove.Move(
                    source: source,
                    destination: source.deletingLastPathComponent().appendingPathComponent(name)
                )
            })
        }

        private mutating func revert(_ changes: [Change]) throws {
            progress.totalItems = changes.count
            // Renames and moves only: reverted together, so swapped names come back.
            if changes.allSatisfy(\.isMove) {
                return try moveAll(changes.reversed().compactMap { change in
                    guard case let .moved(from) = change.kind else { return nil }
                    return BatchMove.Move(source: change.url, destination: from)
                })
            }
            for change in changes.reversed() {
                try checkpoint()
                try revert(change)
                advance()
            }
        }

        private mutating func moveAll(_ moves: [BatchMove.Move]) throws {
            result.changes += try BatchMove.perform(moves, checkpoint: checkpoint) { advance() }
        }

        private mutating func revert(_ change: Change) throws {
            switch change.kind {
            case .created:
                try trashItem(change.url)
            case let .moved(from), let .trashed(from):
                guard !FileManager.default.fileExists(atPath: from.path) else {
                    throw Failure.nameTaken(from.lastPathComponent)
                }
                try FileManager.default.moveItem(at: change.url, to: from)
                result.changes.append(Change(kind: .moved(from: change.url), url: from))
            }
        }

        // MARK: - Helpers

        private static func names(in folder: URL) -> Set<String> {
            Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        }

        private static func sameVolume(_ lhs: URL, _ rhs: URL) -> Bool {
            let key = URLResourceKey.volumeIdentifierKey
            let left = try? lhs.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject
            let right = try? rhs.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject
            return left != nil && left == right
        }

        // ponytail: walks the trees; phase 4's index will give folder sizes instantly.
        /// Total size of files under `urls`.
        static func size(of urls: [URL]) -> Int64 {
            var total: Int64 = 0
            for url in urls {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                guard values?.isDirectory == true else {
                    total += Int64(values?.fileSize ?? 0)
                    continue
                }
                let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey])
                while let file = files?.nextObject() as? URL {
                    total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            return total
        }
    }
}
