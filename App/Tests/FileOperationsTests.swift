@testable import Arbor
import CanvasKit
import FileOpsKit
import XCTest

/// File commands through the app's controllers, on a temporary tree and a fake trash:
/// Root/{Alpha/{a.txt, b.txt}, Beta}.
@MainActor
final class FileOperationsTests: XCTestCase {
    private var root: URL!
    private var trash: URL!
    private var canvas: CanvasViewController!
    private var operations: FileOperationsController!
    private var defaults: UserDefaults!
    private let suite = "FileOperationsTests"

    override func setUp() async throws {
        try await super.setUp()
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileOperationsTests-\(UUID().uuidString)")
        root = base.appendingPathComponent("Root", isDirectory: true)
        trash = base.appendingPathComponent("Trash", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Beta"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Alpha"),
            withIntermediateDirectories: true
        )
        try Data("a".utf8).write(to: root.appendingPathComponent("Alpha/a.txt"))
        try Data("b".utf8).write(to: root.appendingPathComponent("Alpha/b.txt"))
        operations = FileOperationsController(runner: FileOperationRunner(trash: UITestFixture.trash(in: root)))
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        canvas = CanvasViewController(defaults: defaults)
        canvas.loadView()
        canvas.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        canvas.onPerform = { [weak self] operation, name in self?.operations.perform(operation, name: name) }
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition(), message)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path)
    }

    private func panel(_ title: String) -> (id: PanelID, panel: FolderPanelController)? {
        canvas.panels.first { $0.value.title == title }.map { ($0.key, $0.value) }
    }

    /// Opens Root, then its Alpha branch, and waits for both to load.
    private func openAlpha() async throws -> (root: FolderPanelController, alpha: FolderPanelController) {
        canvas.openRoot(root)
        try await waitUntil("root loads") { panel("Root")?.panel.items.count == 2 }
        let rootPanel = try XCTUnwrap(panel("Root")?.panel)
        rootPanel.select(names: ["Alpha"])
        try await waitUntil("alpha loads") { panel("Alpha")?.panel.items.count == 2 }
        return try (rootPanel, XCTUnwrap(panel("Alpha")?.panel))
    }

    func testCopyThenUndoThenRedo() async throws {
        let source = root.appendingPathComponent("Alpha/a.txt")
        operations.perform(
            FileOperation(kind: .copy(into: root.appendingPathComponent("Beta")), sources: [source]),
            name: "Copy"
        )
        try await waitUntil("copied") { exists("Beta/a.txt") && !operations.queue.isBusy }
        XCTAssertEqual(operations.history.undoName, "Copy")

        operations.undo()
        try await waitUntil("undone") { !exists("Beta/a.txt") && !operations.queue.isBusy }
        XCTAssertEqual(operations.history.redoName, "Copy")

        operations.redo()
        try await waitUntil("redone") { exists("Beta/a.txt") && !operations.queue.isBusy }
        XCTAssertEqual(operations.history.undoName, "Copy")
        XCTAssertTrue(exists("Alpha/a.txt"))
    }

    func testBranchFoldersAreNotTargetsOutsideTheActivePanel() async throws {
        let (_, alpha) = try await openAlpha()
        let alphaID = try XCTUnwrap(panel("Alpha")).id
        canvas.activate(alphaID, reveal: false)
        alpha.select(names: ["a.txt"])
        XCTAssertEqual(canvas.operationTargets.map(\.lastPathComponent), ["a.txt"], "Root's Alpha only marks the path")
    }

    func testTrashingTheSelectionAcrossPanels() async throws {
        let (rootPanel, alpha) = try await openAlpha()
        try canvas.activate(XCTUnwrap(panel("Root")).id, reveal: false)
        rootPanel.select(names: ["Alpha", "Beta"])
        alpha.select(names: ["b.txt"])
        // Alpha is a target in the active panel, so b.txt (inside it) is not trashed separately.
        XCTAssertEqual(canvas.operationTargets.map(\.lastPathComponent), ["Alpha", "Beta"])
        canvas.trashSelection()
        try await waitUntil("trashed") { !exists("Alpha") && !exists("Beta") && !operations.queue.isBusy }
        operations.undo()
        try await waitUntil("restored") { exists("Alpha/b.txt") && exists("Beta") && !operations.queue.isBusy }
    }

    func testPlainClickClearsLooseSelectionsElsewhere() async throws {
        let (rootPanel, alpha) = try await openAlpha()
        alpha.select(names: ["a.txt"])
        try canvas.panelClicked(XCTUnwrap(panel("Root")).id)
        XCTAssertEqual(alpha.selectedItems, [], "the file selection in Alpha is cleared")
        XCTAssertEqual(rootPanel.selectedItems.map(\.name), ["Alpha"], "the branch folder stays selected")
        XCTAssertNotNil(panel("Alpha"), "the branch stays open")
    }

    func testDropDestinations() async throws {
        let (rootPanel, _) = try await openAlpha()
        let alphaRow = try XCTUnwrap(rootPanel.rowIndex(forName: "Alpha"))
        XCTAssertEqual(rootPanel.dropDestination(row: alphaRow, onItem: true).lastPathComponent, "Alpha")
        XCTAssertEqual(rootPanel.dropDestination(row: alphaRow, onItem: false), root)
        let file = root.appendingPathComponent("Alpha/a.txt")
        XCTAssertTrue(rootPanel.isUsefulDrop([file], into: root))
        XCTAssertFalse(rootPanel.isUsefulDrop([file], into: root.appendingPathComponent("Alpha")), "already there")
    }

    func testOperationTitles() {
        let folder = URL(fileURLWithPath: "/tmp/Dest")
        let one = [URL(fileURLWithPath: "/tmp/a.txt")]
        XCTAssertEqual(
            FileOperationsController.title(for: FileOperation(kind: .copy(into: folder), sources: one)),
            "Copying “a.txt” to “Dest”"
        )
        XCTAssertEqual(
            FileOperationsController.title(for: FileOperation(kind: .trash, sources: one + one)),
            "Moving 2 items to the Trash"
        )
    }
}
