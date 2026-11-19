@testable import CanvasKit
import XCTest

final class StarLayoutTests: XCTestCase {
    private let size = CGSize(width: 300, height: 200)

    private func center(_ rect: CGRect?) -> CGPoint {
        CGPoint(x: rect?.midX ?? 0, y: rect?.midY ?? 0)
    }

    func testChildrenSurroundTheRootAtEqualDistance() {
        let root = LayoutNode(id: PanelID(), parent: nil, size: size)
        let children = (0 ..< 4).map { _ in LayoutNode(id: PanelID(), parent: root.id, size: size) }
        let frames = LayoutEngine.frames(for: [root] + children, layout: .star, origin: .zero)
        let rootCenter = center(frames[root.id])
        let distances = children.map { child -> CGFloat in
            let point = center(frames[child.id])
            return hypot(point.x - rootCenter.x, point.y - rootCenter.y)
        }
        for distance in distances {
            XCTAssertEqual(distance, distances[0], accuracy: 0.001)
            XCTAssertGreaterThan(distance, hypot(size.width, size.height))
        }
        // One child in each quadrant around the root.
        let quadrants = Set(children.map { child -> String in
            let point = center(frames[child.id])
            return "\(point.x > rootCenter.x)\(point.y > rootCenter.y)"
        })
        XCTAssertEqual(quadrants.count, 4)
        assertNoOverlap(frames)
    }

    func testSingleChildGoesRight() throws {
        let root = LayoutNode(id: PanelID(), parent: nil, size: size)
        let child = LayoutNode(id: PanelID(), parent: root.id, size: size)
        let frames = LayoutEngine.frames(for: [root, child], layout: .star, origin: .zero)
        XCTAssertGreaterThan(try XCTUnwrap(frames[child.id]).minX, try XCTUnwrap(frames[root.id]).maxX)
    }

    func testBoundsStartAtOrigin() {
        let root = LayoutNode(id: PanelID(), parent: nil, size: size)
        let child = LayoutNode(id: PanelID(), parent: root.id, size: size)
        let frames = LayoutEngine.frames(for: [root, child], layout: .star, origin: CGPoint(x: 10, y: 20))
        let bounds = frames.values.reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(bounds.minX, 10, accuracy: 0.001)
        XCTAssertEqual(bounds.minY, 20, accuracy: 0.001)
    }

    func testGeneratedForestsNeverOverlapAndAreDeterministic() {
        for seed in UInt64(1) ... 25 {
            var generator = ForestGenerator(seed: seed)
            let nodes = generator.forest(count: 40)
            let frames = LayoutEngine.frames(for: nodes, layout: .star, origin: .zero)
            XCTAssertEqual(frames.count, nodes.count)
            assertNoOverlap(frames)
            XCTAssertEqual(frames, LayoutEngine.frames(for: nodes, layout: .star, origin: .zero))
        }
    }
}
