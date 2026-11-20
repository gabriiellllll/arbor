import Foundation

/// Runs file operations one at a time on a background thread and publishes their state on
/// the main actor. Conflicts are asked through `resolveConflict`, without blocking the UI.
@MainActor
public final class FileOperationQueue {
    public enum State: Equatable, Sendable {
        case queued
        case running
        case paused
        case done(OperationResult)
    }

    public struct Item: Equatable, Identifiable, Sendable {
        public let operation: FileOperation
        public var state: State
        public var progress: OperationProgress

        public var id: UUID {
            operation.id
        }
    }

    public private(set) var items: [Item] = []
    /// Called after any change to `items`.
    public var onChange: (() -> Void)?
    /// Called when an operation ends (finished, stopped, cancelled or failed).
    public var onFinish: ((FileOperation, OperationResult) -> Void)?
    /// Asked for each conflict. Defaults to skipping.
    public var resolveConflict: (Conflict) async -> ConflictAnswer = { _ in
        ConflictAnswer(decision: .skip, applyToAll: false)
    }

    private let runner: FileOperationRunner
    private let worker = DispatchQueue(label: "app.arbor.FileOperationQueue", qos: .userInitiated)
    private var controls: [UUID: OperationControl] = [:]
    private var running: UUID?

    public init(runner: FileOperationRunner = FileOperationRunner()) {
        self.runner = runner
    }

    @discardableResult
    public func enqueue(_ operation: FileOperation) -> UUID {
        items.append(Item(operation: operation, state: .queued, progress: OperationProgress()))
        controls[operation.id] = OperationControl()
        onChange?()
        startNextIfIdle()
        return operation.id
    }

    public func pause(_ id: UUID) {
        controls[id]?.pause()
        update(id) {
            if $0.state == .running || $0.state == .queued {
                $0.state = .paused
            }
        }
    }

    public func resume(_ id: UUID) {
        controls[id]?.resume()
        update(id) {
            if $0.state == .paused {
                $0.state = id == self.running ? .running : .queued
            }
        }
        startNextIfIdle()
    }

    public func cancel(_ id: UUID) {
        guard let control = controls[id] else { return }
        control.cancel()
        if id != running {
            finish(id, OperationResult(outcome: .cancelled))
        }
    }

    /// Forgets operations that are done.
    public func clearDone() {
        items.removeAll {
            if case .done = $0.state {
                return true
            }
            return false
        }
        onChange?()
    }

    public var isBusy: Bool {
        running != nil || items.contains { $0.state == .queued || $0.state == .paused }
    }

    // MARK: - Running

    private func startNextIfIdle() {
        guard running == nil,
              let next = items.first(where: { $0.state == .queued }),
              let control = controls[next.id] else { return }
        running = next.id
        update(next.id) { $0.state = .running }
        let operation = next.operation
        let runner = runner
        // The queue stays alive while an operation runs.
        worker.async { [self] in
            let result = runner.run(
                operation,
                control: control,
                progress: { progress in
                    Task { @MainActor in self.update(operation.id) { $0.progress = progress } }
                },
                resolve: { conflict in Self.ask(conflict, of: self) }
            )
            Task { @MainActor in
                self.running = nil
                self.finish(operation.id, result)
                self.startNextIfIdle()
            }
        }
    }

    /// Blocks the worker thread until the main actor answers.
    private nonisolated static func ask(_ conflict: Conflict, of queue: FileOperationQueue) -> ConflictAnswer {
        let answer = AnswerBox()
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            answer.value = await queue.resolveConflict(conflict)
            done.signal()
        }
        done.wait()
        return answer.value ?? ConflictAnswer(decision: .stop, applyToAll: false)
    }

    private final class AnswerBox: @unchecked Sendable {
        var value: ConflictAnswer?
    }

    private func finish(_ id: UUID, _ result: OperationResult) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if case .done = items[index].state {
            return
        }
        items[index].state = .done(result)
        controls[id] = nil
        onChange?()
        onFinish?(items[index].operation, result)
    }

    private func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        onChange?()
    }
}

public extension FileOperation {
    /// The operation that undoes `result`, if it changed anything.
    static func undoing(_ result: OperationResult) -> FileOperation? {
        result.changes.isEmpty ? nil : FileOperation(kind: .revert(result.changes), sources: [])
    }
}
