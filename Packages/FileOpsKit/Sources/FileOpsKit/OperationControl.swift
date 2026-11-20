import Foundation

/// Pause, resume and cancel a running operation from another thread.
public final class OperationControl: @unchecked Sendable {
    private let condition = NSCondition()
    private var paused = false
    private var cancelled = false

    public init() {}

    public var isPaused: Bool {
        condition.withLock { paused }
    }

    public var isCancelled: Bool {
        condition.withLock { cancelled }
    }

    public func pause() {
        condition.withLock { paused = true }
    }

    public func resume() {
        condition.withLock {
            paused = false
            condition.broadcast()
        }
    }

    public func cancel() {
        condition.withLock {
            cancelled = true
            condition.broadcast()
        }
    }

    /// Blocks while paused. Returns false if the operation was cancelled.
    func proceed() -> Bool {
        condition.withLock {
            while paused, !cancelled {
                condition.wait()
            }
            return !cancelled
        }
    }
}
