@testable import Arbor
import CanvasKit
import XCTest

/// Drives `CanvasViewController` on a temporary folder tree:
/// Root/{Alpha/{Inner, OnlyA}, Beta/{Inner}, notes.txt}.
@MainActor
final class CanvasControllerTests: XCTestCase {
    private var root: URL!
    private var controller: CanvasViewController!
    private var defaults: UserDefaults!
    private let suite = "CanvasControllerTests"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CanvasControllerTests-\(UUID().uuidString)/Root", isDirectory: true)
        for folder in ["Alpha/Inner", "Alpha/OnlyA", "Beta/Inner"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        try Data().write(to: root.appendingPathComponent("notes.txt"))
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        controller = CanvasViewController(defaults: defaults)
        controller.loadView()
        controller.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        controller.layout = .treeRight
    }

    override func tearDown() async throws {
        controller = nil
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    /// Spins the run loop until `condition` holds (folders load in the background).
    private func waitUntil(_ message: String, _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(condition(), message)
    }

    private func panel(named name: String) -> (id: PanelID, panel: FolderPanelController)? {
        controller.panels.first { $0.value.title == name }.map { ($0.key, $0.value) }
    }

    private func openRootAndWait() -> FolderPanelController? {
        controller.openRoot(root)
        waitUntil("root loads") { panel(named: "Root")?.panel.items.count == 3 }
        return panel(named: "Root")?.panel
    }

    func testSelectingAFolderOpensItAsAChildToTheRight() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        rootPanel.select(names: ["Alpha"])
        let alpha = try XCTUnwrap(panel(named: "Alpha"))
        waitUntil("layout settles") { !controller.animator.isAnimating }
        XCTAssertGreaterThan(alpha.panel.panelView.frame.minX, rootPanel.panelView.frame.maxX)
        XCTAssertEqual(controller.tree[alpha.id]?.sourceKey, "Alpha")
    }

    func testLayoutChoiceIsSavedInTheGivenDefaults() {
        controller.layout = .star
        XCTAssertEqual(defaults.string(forKey: CanvasViewController.layoutDefaultsKey), "star")
        XCTAssertEqual(CanvasViewController(defaults: defaults).layout, .star)
    }

    func testSwitchingToTreeDownMovesChildrenBelow() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        rootPanel.select(names: ["Alpha"])
        controller.layout = .treeDown
        waitUntil("layout settles") { !controller.animator.isAnimating }
        let alpha = try XCTUnwrap(panel(named: "Alpha")).panel
        XCTAssertGreaterThan(alpha.panelView.frame.minY, rootPanel.panelView.frame.maxY)
    }

    func testDraggingAPanelSwitchesToManualAndKeepsIt() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        rootPanel.select(names: ["Alpha"])
        waitUntil("layout settles") { !controller.animator.isAnimating }
        let alpha = try XCTUnwrap(panel(named: "Alpha"))
        let moved = alpha.panel.panelView.frame.offsetBy(dx: 300, dy: 500)
        alpha.panel.panelView.frame = moved
        controller.panelDragged(alpha.id)
        controller.panelDragEnded(alpha.id)
        XCTAssertEqual(controller.layout, .manual)
        XCTAssertEqual(alpha.panel.panelView.frame, moved)

        controller.layout = .star
        waitUntil("layout settles") { !controller.animator.isAnimating }
        XCTAssertNotEqual(alpha.panel.panelView.frame, moved)
        controller.layout = .manual
        waitUntil("manual positions come back") { alpha.panel.panelView.frame == moved }
    }

    func testRootsGetDifferentColorsAndChildrenInheritThem() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        rootPanel.select(names: ["Alpha"])
        let alpha = try XCTUnwrap(panel(named: "Alpha"))
        let rootID = try XCTUnwrap(panel(named: "Root")).id
        XCTAssertEqual(controller.color(of: alpha.id), controller.color(of: rootID))
        controller.openRoot(root.appendingPathComponent("Beta"))
        let beta = try XCTUnwrap(controller.tree.roots.first { $0 != rootID })
        XCTAssertNotEqual(controller.rootColors[beta], controller.rootColors[rootID])
    }

    func testComparisonMirrorsSelectionAndMarksOneSidedItems() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        try controller.activate(XCTUnwrap(panel(named: "Root")).id, reveal: false)
        rootPanel.select(names: ["Alpha", "Beta"])
        waitUntil("both branches load") {
            panel(named: "Alpha")?.panel.items.count == 2 && panel(named: "Beta")?.panel.items.count == 1
        }
        XCTAssertTrue(controller.canCompareSelection, "loading child panels must not steal the active panel")
        controller.compareSelection()
        let compare = try XCTUnwrap(controller.compare)
        XCTAssertTrue(try controller.tree.children(of: XCTUnwrap(panel(named: "Root")).id).isEmpty, "branches replaced")
        let left = try XCTUnwrap(controller.panels[compare.left])
        let right = try XCTUnwrap(controller.panels[compare.right])
        waitUntil("compared folders load") { left.items.count == 2 && right.items.count == 1 }

        left.select(names: ["Inner"])
        waitUntil("the right side follows") { controller.lane(compare.right).count == 2 }
        XCTAssertEqual(controller.lane(compare.left).count, 2)
        XCTAssertEqual(right.selectedItems.map(\.name), ["Inner"])
        XCTAssertEqual(right.counterpartNames, ["Inner", "OnlyA"])
        XCTAssertEqual(left.counterpartNames, ["Inner"], "OnlyA is marked as present on the left only")

        waitUntil("layout settles") { !controller.animator.isAnimating }
        let leftInner = try XCTUnwrap(controller.lane(compare.left).last.flatMap { controller.panels[$0] })
        let rightInner = try XCTUnwrap(controller.lane(compare.right).last.flatMap { controller.panels[$0] })
        XCTAssertEqual(leftInner.panelView.frame.minY, rightInner.panelView.frame.minY, "homologous panels share a row")
        XCTAssertGreaterThan(rightInner.panelView.frame.minX, leftInner.panelView.frame.maxX)
    }

    func testClosingAComparedRootEndsTheComparison() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        try controller.activate(XCTUnwrap(panel(named: "Root")).id, reveal: false)
        rootPanel.select(names: ["Alpha", "Beta"])
        controller.compareSelection()
        let compare = try XCTUnwrap(controller.compare)
        controller.endComparison()
        XCTAssertNil(controller.compare)
        XCTAssertNil(controller.panels[compare.left])
        XCTAssertNil(controller.panels[compare.right])
    }

    func testSnapshotRestoresRootsBranchesLayoutAndColors() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        rootPanel.select(names: ["Alpha"])
        controller.layout = .treeDown
        let rootID = try XCTUnwrap(panel(named: "Root")).id
        let color = controller.rootColors[rootID]
        let data = try JSONEncoder().encode(controller.snapshot())

        let restored = CanvasViewController(defaults: defaults)
        restored.loadView()
        restored.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        try restored.restore(JSONDecoder().decode(CanvasSnapshot.self, from: data))
        waitUntil("the branch reopens") { restored.panels.values.contains { $0.title == "Alpha" } }
        XCTAssertEqual(restored.layout, .treeDown)
        let restoredRoot = try XCTUnwrap(restored.tree.roots.first)
        XCTAssertEqual(restored.rootColors[restoredRoot], color)
        XCTAssertEqual(restored.panels[restoredRoot]?.selectedItems.map(\.name), ["Alpha"])
    }

    func testRestoringAnEmptySnapshotClearsTheCanvas() throws {
        _ = try XCTUnwrap(openRootAndWait())
        controller.restore(CanvasSnapshot())
        XCTAssertTrue(controller.panels.isEmpty)
        XCTAssertTrue(controller.tree.roots.isEmpty)
    }

    func testBackAndForwardRevisitOpenedFolders() throws {
        let rootPanel = try XCTUnwrap(openRootAndWait())
        rootPanel.select(names: ["Alpha"])
        rootPanel.select(names: ["Beta"])
        XCTAssertEqual(
            controller.history.entries.map { URL(fileURLWithPath: $0).lastPathComponent },
            ["Root", "Alpha", "Beta"]
        )

        controller.goBack()
        let alpha = try XCTUnwrap(panel(named: "Alpha"), "the closed folder reopens")
        XCTAssertEqual(controller.activePanel, alpha.id)
        XCTAssertEqual(controller.history.entries.count, 3, "going back records nothing")

        controller.goBack()
        XCTAssertEqual(controller.activePanel, panel(named: "Root")?.id)
        controller.goForward()
        XCTAssertEqual(controller.activePanel, panel(named: "Alpha")?.id)
    }
}
