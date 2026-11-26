import Foundation

/// What a file operation does to its sources.
public enum FileOperationKind: Equatable, Sendable {
    case copy(into: URL)
    case move(into: URL)
    case trash
    case rename(newName: String)
    /// Renames each source to the name at the same index, all or nothing. Items may take each
    /// other's names.
    case renameAll(newNames: [String])
    /// Undoes recorded changes (newest first).
    case revert([Change])
}

public struct FileOperation: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: FileOperationKind
    public let sources: [URL]

    public init(id: UUID = UUID(), kind: FileOperationKind, sources: [URL]) {
        self.id = id
        self.kind = kind
        self.sources = sources
    }
}

/// One change made on disk, enough to undo it. `url` is where the item is now.
public struct Change: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// A new item (copy).
        case created
        /// Moved or renamed from that location.
        case moved(from: URL)
        /// Moved to the trash from that location.
        case trashed(from: URL)
    }

    public let kind: Kind
    public let url: URL

    var isMove: Bool {
        if case .moved = kind {
            return true
        }
        return false
    }

    public init(kind: Kind, url: URL) {
        self.kind = kind
        self.url = url
    }
}

/// An item already exists where a source would go.
public struct Conflict: Sendable {
    public let source: URL
    public let existing: URL
}

public enum ConflictDecision: Sendable {
    /// Moves the existing item to the trash, then puts the new one in place.
    case replace
    /// Keeps the existing item and gives the new one a numbered name.
    case keepBoth
    case skip
    /// Ends the operation.
    case stop
}

public struct ConflictAnswer: Sendable {
    public let decision: ConflictDecision
    /// Use this decision for the remaining conflicts of the operation.
    public let applyToAll: Bool

    public init(decision: ConflictDecision, applyToAll: Bool) {
        self.decision = decision
        self.applyToAll = applyToAll
    }
}

public struct OperationProgress: Equatable, Sendable {
    public var completedBytes: Int64 = 0
    public var totalBytes: Int64 = 0
    public var completedItems = 0
    public var totalItems = 0

    /// 0 to 1, by bytes when known, otherwise by items.
    public var fraction: Double {
        if totalBytes > 0 {
            return min(Double(completedBytes) / Double(totalBytes), 1)
        }
        return totalItems > 0 ? Double(completedItems) / Double(totalItems) : 0
    }
}

public enum OperationOutcome: Equatable, Sendable {
    case finished
    /// The user chose Stop at a conflict.
    case stopped
    case cancelled
    case failed(String)
}

public struct OperationResult: Equatable, Sendable {
    public var outcome: OperationOutcome = .finished
    /// Changes made, in order, including those before a stop, cancel or failure.
    public var changes: [Change] = []
    public var skipped: [URL] = []
}
