@testable import FileOpsKit
import Foundation
import XCTest

/// A temporary sandbox with a fake trash, so tests never touch the user's files or Trash.
final class Sandbox {
    let root: URL
    let trashFolder: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileOpsKitTests-\(UUID().uuidString)", isDirectory: true)
        trashFolder = root.appendingPathComponent(".FakeTrash", isDirectory: true)
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func file(_ path: String, _ content: String = "content") throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: url)
        return url
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func url(_ path: String) -> URL {
        root.appendingPathComponent(path)
    }

    func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    func read(_ path: String) -> String? {
        (try? Data(contentsOf: url(path))).flatMap { String(bytes: $0, encoding: .utf8) }
    }

    /// Moves items into the sandbox's fake trash, like the system trash would.
    var trash: FileOperationRunner.Trash {
        let folder = trashFolder
        return { url in
            let slot = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let destination = slot.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    func runner(allowsClone: Bool = true) -> FileOperationRunner {
        FileOperationRunner(trash: trash, allowsClone: allowsClone)
    }

    /// Runs `operation`, answering every conflict with `decision`.
    func run(
        _ operation: FileOperation, decision: ConflictDecision = .skip, applyToAll: Bool = false,
        conflicts: ConflictCounter = ConflictCounter()
    ) -> OperationResult {
        runner().run(operation, control: OperationControl(), progress: { _ in }, resolve: { _ in
            conflicts.increment()
            return ConflictAnswer(decision: decision, applyToAll: applyToAll)
        })
    }
}

/// Counts conflict prompts from the runner's thread.
final class ConflictCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.withLock { value += 1 }
    }

    var count: Int {
        lock.withLock { value }
    }
}
