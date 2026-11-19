@testable import CanvasKit
import XCTest

final class TreeLayoutTests: XCTestCase {
    private let size = CGSize(width: 300, height: 200)

    /// Root with two children; the first child has one child.
    private struct Sample {
        let root: LayoutNode
        let children: [LayoutNode]
        let grandchild: LayoutNode

        var all: [LayoutNode] {
            [root] + children + [grandchild]
        }
    }

    private func sample() -> Sample {
        let root = LayoutNode(id: PanelID(), parent: nil, size: size)
        let first = LayoutNode(id: PanelID(), parent: root.id, size: size)
        let second = LayoutNode(id: PanelID(), parent: root.id, size: size)
        let grandchild = LayoutNode(id: PanelID(), parent: first.id, size: size)
        return Sample(root: root, children: [first, second], grandchild: grandchild)
    }

    func testManualLayoutLeavesFramesAlone() {
        XCTAssertTrue(LayoutEngine.frames(for: sample().all, layout: .manual, origin: .zero).isEmpty)
    }

    func testTreeRightPlacesChildrenInColumnsInOrder() throws {
        let tree = sample()
        let (root, children, grandchild) = (tree.root, tree.children, tree.grandchild)
        let frames = LayoutEngine.frames(for: tree.all, layout: .treeRight, origin: .zero)
        let rootFrame = try XCTUnwrap(frames[root.id])
        let first = try XCTUnwrap(frames[children[0].id])
        let second = try XCTUnwrap(frames[children[1].id])
        let deep = try XCTUnwrap(frames[grandchild.id])
        XCTAssertEqual(rootFrame.origin, .zero)
        XCTAssertEqual(first.minX, rootFrame.maxX + LayoutEngine.columnGap)
        XCTAssertEqual(first.minY, rootFrame.minY, "parent is top-aligned with its first child")
        XCTAssertEqual(second.minX, first.minX)
        XCTAssertGreaterThan(second.minY, first.maxY, "siblings keep their order top to bottom")
        XCTAssertEqual(deep.minX, first.maxX + LayoutEngine.columnGap)
        assertNoOverlap(frames)
    }

    func testTreeDownPlacesChildrenInRowsInOrder() throws {
        let tree = sample()
        let (root, children) = (tree.root, tree.children)
        let frames = LayoutEngine.frames(for: tree.all, layout: .treeDown, origin: .zero)
        let rootFrame = try XCTUnwrap(frames[root.id])
        let first = try XCTUnwrap(frames[children[0].id])
        let second = try XCTUnwrap(frames[children[1].id])
        XCTAssertEqual(first.minY, rootFrame.maxY + LayoutEngine.levelGap)
        XCTAssertEqual(first.minX, rootFrame.minX)
        XCTAssertGreaterThan(second.minX, first.maxX, "siblings keep their order left to right")
        assertNoOverlap(frames)
    }

    func testRootsAreStackedWithoutOverlap() {
        let roots = (0 ..< 3).map { _ in LayoutNode(id: PanelID(), parent: nil, size: size) }
        for layout in [CanvasLayout.treeRight, .treeDown] {
            let frames = LayoutEngine.frames(for: roots, layout: layout, origin: CGPoint(x: 50, y: 70))
            XCTAssertEqual(frames[roots[0].id]?.origin, CGPoint(x: 50, y: 70))
            assertNoOverlap(frames)
        }
    }

    func testGeneratedForestsNeverOverlapAndAreDeterministic() {
        for seed in UInt64(1) ... 25 {
            var generator = ForestGenerator(seed: seed)
            let nodes = generator.forest(count: 40)
            for layout in [CanvasLayout.treeRight, .treeDown] {
                let frames = LayoutEngine.frames(for: nodes, layout: layout, origin: .zero)
                XCTAssertEqual(frames.count, nodes.count)
                assertNoOverlap(frames)
                XCTAssertEqual(frames, LayoutEngine.frames(for: nodes, layout: layout, origin: .zero))
            }
        }
    }

    func testFramesKeepPanelSizes() {
        var generator = ForestGenerator(seed: 7)
        let nodes = generator.forest(count: 15)
        let frames = LayoutEngine.frames(for: nodes, layout: .treeRight, origin: .zero)
        for node in nodes {
            XCTAssertEqual(frames[node.id]?.size, node.size)
        }
    }
}
