@testable import FileOpsKit
import XCTest

@MainActor
final class FileOperationQueueTests: XCTestCase {
    private var box: Sandbox!
    private var queue: FileOperationQueue!

    override func setUp() async throws {
        box = try Sandbox()
        queue = FileOperationQueue(runner: box.runner(allowsClone: false))
    }

    override func tearDown() async throws {
        queue = nil
        box = nil
    }

    private func waitUntilIdle() async throws {
        let deadline = Date().addingTimeInterval(10)
        while queue.isBusy, Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(queue.isBusy)
    }

    private func outcome(_ id: UUID) -> OperationOutcome? {
        guard case let .done(result) = queue.items.first(where: { $0.id == id })?.state else { return nil }
        return result.outcome
    }

    func testRunsOperationsOneAfterAnother() async throws {
        let big = box.url("big.bin")
        try Data(repeating: 1, count: 32 * 1024 * 1024).write(to: big)
        let small = try box.file("a.txt")
        let destination = try box.folder("dest")
        var finished: [FileOperationKind] = []
        queue.onFinish = { operation, _ in finished.append(operation.kind) }

        let first = queue.enqueue(FileOperation(kind: .copy(into: destination), sources: [big]))
        let second = queue.enqueue(FileOperation(kind: .trash, sources: [small]))
        XCTAssertEqual(queue.items.map(\.state), [.running, .queued])

        try await waitUntilIdle()
        XCTAssertEqual(outcome(first), .finished)
        XCTAssertEqual(outcome(second), .finished)
        XCTAssertEqual(finished, [.copy(into: destination), .trash])
    }

    func testCancellingAQueuedOperationNeverRunsIt() async throws {
        let big = box.url("big.bin")
        try Data(repeating: 1, count: 32 * 1024 * 1024).write(to: big)
        let small = try box.file("a.txt")
        try queue.enqueue(FileOperation(kind: .copy(into: box.folder("dest")), sources: [big]))
        let second = queue.enqueue(FileOperation(kind: .trash, sources: [small]))
        queue.cancel(second)
        try await waitUntilIdle()
        XCTAssertEqual(outcome(second), .cancelled)
        XCTAssertTrue(box.exists("a.txt"))
    }

    func testConflictsAreAskedAsynchronously() async throws {
        let source = try box.file("a.txt", "new")
        try box.file("dest/a.txt", "old")
        var asked: [String] = []
        queue.resolveConflict = { conflict in
            asked.append(conflict.existing.lastPathComponent)
            try? await Task.sleep(for: .milliseconds(50))
            return ConflictAnswer(decision: .keepBoth, applyToAll: false)
        }
        queue.enqueue(FileOperation(kind: .copy(into: box.url("dest")), sources: [source]))
        try await waitUntilIdle()
        XCTAssertEqual(asked, ["a.txt"])
        XCTAssertEqual(box.read("dest/a 2.txt"), "new")
    }

    func testPausedOperationWaitsForResume() async throws {
        let small = try box.file("a.txt")
        // Pause before it starts: the queue holds it.
        let big = box.url("big.bin")
        try Data(repeating: 1, count: 32 * 1024 * 1024).write(to: big)
        try queue.enqueue(FileOperation(kind: .copy(into: box.folder("dest")), sources: [big]))
        let id = queue.enqueue(FileOperation(kind: .trash, sources: [small]))
        queue.pause(id)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(queue.items.last?.state, .paused)
        XCTAssertTrue(box.exists("a.txt"))
        queue.resume(id)
        try await waitUntilIdle()
        XCTAssertEqual(outcome(id), .finished)
        XCTAssertFalse(box.exists("a.txt"))
    }

    func testUndoingAResultRevertsIt() async throws {
        let source = try box.file("a.txt", "x")
        var undo: FileOperation?
        queue.onFinish = { _, result in undo = FileOperation.undoing(result) }
        try queue.enqueue(FileOperation(kind: .move(into: box.folder("dest")), sources: [source]))
        try await waitUntilIdle()
        try queue.enqueue(XCTUnwrap(undo))
        try await waitUntilIdle()
        XCTAssertEqual(box.read("a.txt"), "x")
        XCTAssertNil(FileOperation.undoing(OperationResult()), "nothing to undo")
    }

    func testClearDoneKeepsRunningItems() async throws {
        try queue.enqueue(FileOperation(kind: .trash, sources: [box.file("a.txt")]))
        try await waitUntilIdle()
        queue.clearDone()
        XCTAssertTrue(queue.items.isEmpty)
    }
}
