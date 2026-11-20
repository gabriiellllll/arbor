@testable import FileOpsKit
import XCTest

/// Progress, pause and cancel on a real, chunked copy (clones disabled).
final class OperationControlTests: XCTestCase {
    private var box: Sandbox!
    private var big: URL!
    private let size = 64 * 1024 * 1024

    override func setUpWithError() throws {
        box = try Sandbox()
        big = box.url("big.bin")
        try Data(repeating: 7, count: size).write(to: big)
        try box.folder("dest")
    }

    override func tearDown() {
        box = nil
    }

    /// Collects progress reports from the runner's thread.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [OperationProgress] = []
        var onFirstBytes: (() -> Void)?

        func record(_ progress: OperationProgress) {
            let first = lock.withLock {
                values.append(progress)
                return values.count(where: { $0.completedBytes > 0 }) == 1 && progress.completedBytes > 0
            }
            if first {
                onFirstBytes?()
            }
        }

        var all: [OperationProgress] {
            lock.withLock { values }
        }
    }

    private func copy(control: OperationControl, recorder: Recorder) -> OperationResult {
        box.runner(allowsClone: false).run(
            FileOperation(kind: .copy(into: box.url("dest")), sources: [big]),
            control: control,
            progress: { recorder.record($0) },
            resolve: { _ in ConflictAnswer(decision: .skip, applyToAll: false) }
        )
    }

    func testProgressGrowsToTheTotal() {
        let recorder = Recorder()
        XCTAssertEqual(copy(control: OperationControl(), recorder: recorder).outcome, .finished)
        let reports = recorder.all
        XCTAssertGreaterThan(reports.count, 2, "chunked progress, not just start and end")
        XCTAssertEqual(reports.map(\.completedBytes), reports.map(\.completedBytes).sorted())
        XCTAssertEqual(reports.last?.completedBytes, Int64(size))
        XCTAssertEqual(reports.last?.fraction, 1)
        XCTAssertEqual(reports.last?.completedItems, 1)
    }

    func testCancelStopsAndRemovesThePartialCopy() {
        let control = OperationControl()
        let recorder = Recorder()
        recorder.onFirstBytes = { control.cancel() }
        let result = copy(control: control, recorder: recorder)
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertFalse(box.exists("dest/big.bin"))
        XCTAssertTrue(box.exists("big.bin"))
        XCTAssertEqual(result.changes, [])
    }

    func testPauseHoldsTheCopyUntilResumed() {
        let control = OperationControl()
        let recorder = Recorder()
        recorder.onFirstBytes = {
            control.pause()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { control.resume() }
        }
        let started = Date()
        let result = copy(control: control, recorder: recorder)
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertGreaterThanOrEqual(Date().timeIntervalSince(started), 0.3)
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: box.url("dest/big.bin").path)[.size] as? Int,
            size
        )
    }

    func testCancelWhilePausedEndsTheOperation() {
        let control = OperationControl()
        let recorder = Recorder()
        recorder.onFirstBytes = {
            control.pause()
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { control.cancel() }
        }
        XCTAssertEqual(copy(control: control, recorder: recorder).outcome, .cancelled)
        XCTAssertFalse(box.exists("dest/big.bin"))
    }

    func testCancelBeforeStartingDoesNothing() throws {
        let control = OperationControl()
        control.cancel()
        let small = try box.file("a.txt")
        let result = box.runner().run(
            FileOperation(kind: .trash, sources: [small]), control: control, progress: { _ in },
            resolve: { _ in ConflictAnswer(decision: .skip, applyToAll: false) }
        )
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertTrue(box.exists("a.txt"))
    }
}
