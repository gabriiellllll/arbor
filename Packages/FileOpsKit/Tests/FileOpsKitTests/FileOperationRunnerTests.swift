@testable import FileOpsKit
import XCTest

final class FileOperationRunnerTests: XCTestCase {
    private var box: Sandbox!

    override func setUpWithError() throws {
        box = try Sandbox()
    }

    override func tearDown() {
        box = nil
    }

    // MARK: - Copy

    func testCopiesAFileIntoAFolder() throws {
        let source = try box.file("a.txt", "hello")
        let destination = try box.folder("dest")
        let result = box.run(FileOperation(kind: .copy(into: destination), sources: [source]))
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertEqual(box.read("dest/a.txt"), "hello")
        XCTAssertTrue(box.exists("a.txt"), "the source stays")
        XCTAssertEqual(result.changes, [Change(kind: .created, url: destination.appendingPathComponent("a.txt"))])
    }

    func testCopiesFoldersRecursivelyWithTheirTags() throws {
        let folder = try box.folder("src")
        let nested = try box.file("src/inner/b.txt", "deep")
        try FinderTags.setTags(["Blue"], on: nested)
        let destination = try box.folder("dest")
        XCTAssertEqual(box.run(FileOperation(kind: .copy(into: destination), sources: [folder])).outcome, .finished)
        XCTAssertEqual(box.read("dest/src/inner/b.txt"), "deep")
        XCTAssertEqual(try FinderTags.tags(of: box.url("dest/src/inner/b.txt")), ["Blue"])
    }

    func testCopyingIntoTheSameFolderKeepsBoth() throws {
        let source = try box.file("a.txt", "one")
        let result = box.run(FileOperation(kind: .copy(into: box.root), sources: [source]))
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertEqual(box.read("a 2.txt"), "one")
    }

    func testCopyingAFolderIntoItselfFails() throws {
        let folder = try box.folder("src")
        let inside = try box.folder("src/inside")
        let result = box.run(FileOperation(kind: .copy(into: inside), sources: [folder]))
        guard case .failed = result.outcome else { return XCTFail("expected a failure, got \(result.outcome)") }
        XCTAssertFalse(box.exists("src/inside/src"))
    }

    // MARK: - Conflicts

    func testReplaceTrashesTheExistingItemFirst() throws {
        let source = try box.file("a.txt", "new")
        let existing = try box.file("dest/a.txt", "old")
        let result = box.run(FileOperation(kind: .copy(into: box.url("dest")), sources: [source]), decision: .replace)
        XCTAssertEqual(box.read("dest/a.txt"), "new")
        guard case let .trashed(from) = result.changes.first?.kind else { return XCTFail("existing item not trashed") }
        XCTAssertEqual(from, existing)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(result.changes.first?.url), encoding: .utf8), "old")
    }

    func testKeepBothRenamesTheNewItem() throws {
        let source = try box.file("a.txt", "new")
        try box.file("dest/a.txt", "old")
        _ = box.run(FileOperation(kind: .copy(into: box.url("dest")), sources: [source]), decision: .keepBoth)
        XCTAssertEqual(box.read("dest/a.txt"), "old")
        XCTAssertEqual(box.read("dest/a 2.txt"), "new")
    }

    func testSkipLeavesTheExistingItem() throws {
        let source = try box.file("a.txt", "new")
        try box.file("dest/a.txt", "old")
        let result = box.run(FileOperation(kind: .copy(into: box.url("dest")), sources: [source]), decision: .skip)
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertEqual(result.skipped, [source])
        XCTAssertEqual(box.read("dest/a.txt"), "old")
    }

    func testStopEndsTheOperation() throws {
        let first = try box.file("a.txt")
        let second = try box.file("b.txt")
        try box.file("dest/a.txt")
        let result = box.run(
            FileOperation(kind: .copy(into: box.url("dest")), sources: [first, second]),
            decision: .stop
        )
        XCTAssertEqual(result.outcome, .stopped)
        XCTAssertFalse(box.exists("dest/b.txt"), "nothing after the stop")
    }

    func testApplyToAllAsksOnce() throws {
        let first = try box.file("a.txt", "new a")
        let second = try box.file("b.txt", "new b")
        try box.file("dest/a.txt")
        try box.file("dest/b.txt")
        let counter = ConflictCounter()
        _ = box.run(
            FileOperation(kind: .copy(into: box.url("dest")), sources: [first, second]),
            decision: .replace, applyToAll: true, conflicts: counter
        )
        XCTAssertEqual(counter.count, 1)
        XCTAssertEqual(box.read("dest/b.txt"), "new b")
    }

    // MARK: - Move, trash, rename

    func testMovesWithinAVolume() throws {
        let source = try box.file("a.txt", "x")
        let destination = try box.folder("dest")
        let result = box.run(FileOperation(kind: .move(into: destination), sources: [source]))
        XCTAssertFalse(box.exists("a.txt"))
        XCTAssertEqual(box.read("dest/a.txt"), "x")
        XCTAssertEqual(
            result.changes,
            [Change(kind: .moved(from: source), url: destination.appendingPathComponent("a.txt"))]
        )
    }

    func testMovingIntoTheSameFolderChangesNothing() throws {
        let source = try box.file("a.txt")
        let result = box.run(FileOperation(kind: .move(into: box.root), sources: [source]))
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertEqual(result.changes, [])
        XCTAssertTrue(box.exists("a.txt"))
    }

    func testTrashMovesItemsToTheTrash() throws {
        let source = try box.file("a.txt")
        let result = box.run(FileOperation(kind: .trash, sources: [source]))
        XCTAssertFalse(box.exists("a.txt"))
        guard case let .trashed(from) = result.changes.first?.kind else { return XCTFail("not trashed") }
        XCTAssertEqual(from, source)
    }

    func testRename() throws {
        let source = try box.file("a.txt", "x")
        let result = box.run(FileOperation(kind: .rename(newName: "b.txt"), sources: [source]))
        XCTAssertEqual(result.outcome, .finished)
        XCTAssertEqual(box.read("b.txt"), "x")
        XCTAssertFalse(box.exists("a.txt"))
    }

    func testRenameOnlyChangingCase() throws {
        let source = try box.file("readme.md")
        XCTAssertEqual(
            box.run(FileOperation(kind: .rename(newName: "README.md"), sources: [source])).outcome,
            .finished
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: box.root.path).filter { !$0.hasPrefix(".") },
            ["README.md"]
        )
    }

    func testRenameToATakenOrInvalidNameFails() throws {
        let source = try box.file("a.txt")
        try box.file("b.txt")
        for name in ["b.txt", "", "x/y", "x:y"] {
            guard case .failed = box.run(FileOperation(kind: .rename(newName: name), sources: [source])).outcome else {
                return XCTFail("renaming to \"\(name)\" should fail")
            }
        }
        XCTAssertTrue(box.exists("a.txt"))
    }

    // MARK: - Revert

    func testRevertingACopyTrashesTheCopies() throws {
        let source = try box.file("a.txt")
        let copy = try box.run(FileOperation(kind: .copy(into: box.folder("dest")), sources: [source]))
        _ = box.run(FileOperation(kind: .revert(copy.changes), sources: []))
        XCTAssertFalse(box.exists("dest/a.txt"))
        XCTAssertTrue(box.exists("a.txt"))
    }

    func testRevertingAMoveMovesBack() throws {
        let source = try box.file("a.txt", "x")
        let move = try box.run(FileOperation(kind: .move(into: box.folder("dest")), sources: [source]))
        _ = box.run(FileOperation(kind: .revert(move.changes), sources: []))
        XCTAssertEqual(box.read("a.txt"), "x")
        XCTAssertFalse(box.exists("dest/a.txt"))
    }

    func testRevertingATrashPutsBack() throws {
        let source = try box.file("a.txt", "x")
        let trash = box.run(FileOperation(kind: .trash, sources: [source]))
        _ = box.run(FileOperation(kind: .revert(trash.changes), sources: []))
        XCTAssertEqual(box.read("a.txt"), "x")
    }

    func testRevertingAReplaceRestoresTheOriginal() throws {
        let source = try box.file("a.txt", "new")
        try box.file("dest/a.txt", "old")
        let copy = box.run(FileOperation(kind: .copy(into: box.url("dest")), sources: [source]), decision: .replace)
        _ = box.run(FileOperation(kind: .revert(copy.changes), sources: []))
        XCTAssertEqual(box.read("dest/a.txt"), "old")
    }
}
