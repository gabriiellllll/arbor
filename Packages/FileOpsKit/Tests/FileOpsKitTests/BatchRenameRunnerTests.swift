@testable import FileOpsKit
import XCTest

final class BatchRenameRunnerTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    private func visibleNames(in folder: String = "") throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: box.url(folder).path)
            .filter { !$0.hasPrefix(".") }.sorted()
    }

    func testItemsCanSwapNamesAndUndoSwapsThemBack() throws {
        let one = try box.file("a.txt", "one")
        let two = try box.file("b.txt", "two")
        let result = box.run(FileOperation(kind: .renameAll(newNames: ["b.txt", "a.txt"]), sources: [one, two]))
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertEqual(box.read("b.txt"), "one")
        XCTAssertEqual(box.read("a.txt"), "two")
        XCTAssertEqual(result.changes.count, 2)

        let undo = try XCTUnwrap(FileOperation.undoing(result))
        XCTAssertEqual(box.run(undo).outcome, .finished)
        XCTAssertEqual(box.read("a.txt"), "one")
        XCTAssertEqual(box.read("b.txt"), "two")
        XCTAssertEqual(try visibleNames(), ["a.txt", "b.txt"])
    }

    func testChainsAndCaseOnlyChangesAcrossFolders() throws {
        let first = try box.file("x/a", "1")
        let second = try box.file("x/aa", "2")
        let third = try box.file("y/photo.jpg", "3")
        let result = box.run(FileOperation(
            kind: .renameAll(newNames: ["aa", "aaa", "PHOTO.jpg"]), sources: [first, second, third]
        ))
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertEqual(try visibleNames(in: "x"), ["aa", "aaa"])
        XCTAssertEqual(box.read("x/aaa"), "2")
        XCTAssertEqual(try visibleNames(in: "y"), ["PHOTO.jpg"])
    }

    func testATakenNameChangesNothing() throws {
        let one = try box.file("a.txt", "one")
        let two = try box.file("b.txt", "two")
        try box.file("taken.txt", "other")
        let result = box.run(FileOperation(kind: .renameAll(newNames: ["c.txt", "taken.txt"]), sources: [one, two]))
        guard case .failed = result.outcome else { return XCTFail("expected a failure, got \(result.outcome)") }
        XCTAssertEqual(result.changes, [])
        XCTAssertEqual(try visibleNames(), ["a.txt", "b.txt", "taken.txt"])
        XCTAssertEqual(box.read("taken.txt"), "other")
    }

    func testInvalidNameChangesNothing() throws {
        let one = try box.file("a.txt")
        let two = try box.file("b.txt")
        let result = box.run(FileOperation(kind: .renameAll(newNames: ["c.txt", "d:e"]), sources: [one, two]))
        guard case .failed = result.outcome else { return XCTFail("expected a failure") }
        XCTAssertEqual(try visibleNames(), ["a.txt", "b.txt"])
    }

    func testCancelledBeforeStartChangesNothing() throws {
        let one = try box.file("a.txt")
        let control = OperationControl()
        control.cancel()
        let result = box.runner().run(
            FileOperation(kind: .renameAll(newNames: ["b.txt"]), sources: [one]),
            control: control, progress: { _ in }, resolve: { _ in ConflictAnswer(decision: .skip, applyToAll: false) }
        )
        XCTAssertEqual(result.outcome, .cancelled)
        XCTAssertEqual(try visibleNames(), ["a.txt"])
    }
}
