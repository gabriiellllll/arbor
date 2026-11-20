@testable import FileOpsKit
import XCTest

final class UndoHistoryTests: XCTestCase {
    private let url = URL(fileURLWithPath: "/tmp/a")

    private func done(_ kind: FileOperationKind) -> (FileOperation, OperationResult) {
        let operation = FileOperation(kind: kind, sources: [url])
        var result = OperationResult()
        result.changes = [Change(kind: .created, url: url)]
        return (operation, result)
    }

    func testUndoReturnsTheRevertOfTheLastAction() throws {
        var history = UndoHistory()
        let (operation, result) = done(.trash)
        history.record(operation, result: result, name: "Move to Trash")
        XCTAssertEqual(history.undoName, "Move to Trash")
        let revert = try XCTUnwrap(history.undo())
        XCTAssertEqual(revert.kind, .revert(result.changes))
        XCTAssertNil(history.undoName)
        XCTAssertEqual(history.redoName, "Move to Trash")
    }

    func testRedoRunsTheOriginalAgainAsANewOperation() throws {
        var history = UndoHistory()
        let (operation, result) = done(.trash)
        history.record(operation, result: result, name: "Move to Trash")
        _ = history.undo()
        let redo = try XCTUnwrap(history.redo())
        XCTAssertEqual(redo.operation.kind, operation.kind)
        XCTAssertEqual(redo.operation.sources, operation.sources)
        XCTAssertNotEqual(redo.operation.id, operation.id)
        history.recordRedone(redo.operation, result: result, name: redo.name)
        XCTAssertEqual(history.undoName, "Move to Trash")
    }

    func testANewActionClearsRedo() {
        var history = UndoHistory()
        let (first, firstResult) = done(.trash)
        history.record(first, result: firstResult, name: "One")
        _ = history.undo()
        let (second, secondResult) = done(.trash)
        history.record(second, result: secondResult, name: "Two")
        XCTAssertNil(history.redoName)
    }

    func testRedoingKeepsTheRestOfTheRedoStack() {
        var history = UndoHistory()
        for name in ["One", "Two"] {
            let (operation, result) = done(.trash)
            history.record(operation, result: result, name: name)
        }
        _ = history.undo()
        _ = history.undo()
        let redo = history.redo()
        let (_, result) = done(.trash)
        if let redo {
            history.recordRedone(redo.operation, result: result, name: redo.name)
        }
        XCTAssertEqual(history.redoName, "Two")
    }

    func testActionsWithoutChangesAreNotRecorded() {
        var history = UndoHistory()
        history.record(FileOperation(kind: .trash, sources: []), result: OperationResult(), name: "Nothing")
        XCTAssertNil(history.undoName)
        XCTAssertNil(history.undo())
        XCTAssertNil(history.redo())
    }
}
