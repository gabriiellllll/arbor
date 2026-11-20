/// Undo and redo for asynchronous file operations. NSUndoManager expects undo actions to be
/// registered while an action runs; file operations only know their changes when they end.
public struct UndoHistory: Sendable {
    public struct Entry: Equatable, Sendable {
        /// What the user did (run again to redo).
        public let operation: FileOperation
        /// What it changed (reverted to undo).
        public let result: OperationResult
        /// For the Undo / Redo menu titles.
        public let name: String
    }

    public private(set) var undoStack: [Entry] = []
    public private(set) var redoStack: [Entry] = []

    public init() {}

    public var undoName: String? {
        undoStack.last?.name
    }

    public var redoName: String? {
        redoStack.last?.name
    }

    /// Records a finished user operation. Clears redo, like any new action.
    public mutating func record(_ operation: FileOperation, result: OperationResult, name: String) {
        guard !result.changes.isEmpty else { return }
        undoStack.append(Entry(operation: operation, result: result, name: name))
        redoStack.removeAll()
    }

    /// Takes the last action off the undo stack and returns the operation that reverts it.
    public mutating func undo() -> FileOperation? {
        guard let entry = undoStack.popLast(), let revert = FileOperation.undoing(entry.result) else { return nil }
        redoStack.append(entry)
        return revert
    }

    /// Takes the last undone action and returns it as a new operation to run again. Call
    /// `recordRedone` with its result.
    public mutating func redo() -> (operation: FileOperation, name: String)? {
        guard let entry = redoStack.popLast() else { return nil }
        return (FileOperation(kind: entry.operation.kind, sources: entry.operation.sources), entry.name)
    }

    /// Records the result of a redone operation, keeping the rest of the redo stack.
    public mutating func recordRedone(_ operation: FileOperation, result: OperationResult, name: String) {
        guard !result.changes.isEmpty else { return }
        undoStack.append(Entry(operation: operation, result: result, name: name))
    }
}
