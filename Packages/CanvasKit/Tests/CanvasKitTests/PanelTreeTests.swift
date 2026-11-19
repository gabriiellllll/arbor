@testable import CanvasKit
import XCTest

final class PanelTreeTests: XCTestCase {
    private var tree = PanelTree<String>()
    private let frame = CGRect(x: 0, y: 0, width: 300, height: 400)

    private func sync(_ parent: PanelID, _ keys: [String]) -> PanelTree<String>.SyncResult {
        tree.syncChildren(of: parent, to: keys.map { ($0, "/root/\($0)") }) { _, _ in self.frame }
    }

    func testAddRootStoresPanel() {
        let root = tree.addRoot(content: "/root", frame: frame)
        XCTAssertEqual(tree[root]?.content, "/root")
        XCTAssertNil(tree[root]?.parent)
        XCTAssertEqual(tree.roots, [root])
    }

    func testSyncOpensRequestedChildren() {
        let root = tree.addRoot(content: "/root", frame: frame)
        let result = sync(root, ["a", "b"])
        XCTAssertEqual(result.added.count, 2)
        XCTAssertEqual(tree.children(of: root).map(\.sourceKey), ["a", "b"])
        XCTAssertEqual(tree.children(of: root).map(\.content), ["/root/a", "/root/b"])
    }

    func testSelectingAnotherSiblingReplacesTheBranchAndItsDescendants() {
        let root = tree.addRoot(content: "/root", frame: frame)
        let first = sync(root, ["a"]).added[0]
        let grandchild = sync(first, ["deep"]).added[0]
        let result = sync(root, ["b"])
        XCTAssertEqual(Set(result.removed), [first, grandchild])
        XCTAssertNil(tree[first])
        XCTAssertNil(tree[grandchild])
        XCTAssertEqual(tree.children(of: root).map(\.sourceKey), ["b"])
    }

    func testKeptChildrenKeepTheirIdentityAndSubtree() {
        let root = tree.addRoot(content: "/root", frame: frame)
        let first = sync(root, ["a"]).added[0]
        let grandchild = sync(first, ["deep"]).added[0]
        let result = sync(root, ["a", "b"])
        XCTAssertEqual(result.removed, [])
        XCTAssertEqual(result.added.count, 1)
        XCTAssertNotNil(tree[grandchild])
    }

    func testPlacementSeesParentAndKey() {
        let root = tree.addRoot(content: "/root", frame: frame)
        var seen: [String] = []
        _ = tree.syncChildren(of: root, to: [("x", "/root/x")]) { parent, key in
            seen.append("\(parent.content):\(key)")
            return self.frame
        }
        XCTAssertEqual(seen, ["/root:x"])
    }

    func testChainGoesFromRootToPanel() {
        let root = tree.addRoot(content: "/root", frame: frame)
        let child = sync(root, ["a"]).added[0]
        let grandchild = sync(child, ["b"]).added[0]
        XCTAssertEqual(tree.chain(to: grandchild), [root, child, grandchild])
    }

    func testRemoveDropsDescendants() {
        let root = tree.addRoot(content: "/root", frame: frame)
        let child = sync(root, ["a"]).added[0]
        XCTAssertEqual(Set(tree.remove(root)), [root, child])
        XCTAssertTrue(tree.roots.isEmpty)
        XCTAssertTrue(tree.panels.isEmpty)
    }

    func testSetFrameUpdatesPanel() {
        let root = tree.addRoot(content: "/root", frame: frame)
        let moved = frame.offsetBy(dx: 50, dy: 60)
        tree.setFrame(moved, for: root)
        XCTAssertEqual(tree[root]?.frame, moved)
    }
}
