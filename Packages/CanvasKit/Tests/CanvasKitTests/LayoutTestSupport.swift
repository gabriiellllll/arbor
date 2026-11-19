@testable import CanvasKit
import CoreGraphics
import XCTest

/// Deterministic pseudo-random forests for layout tests.
struct ForestGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    private mutating func next(_ bound: Int) -> Int {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((state >> 33) % UInt64(bound))
    }

    /// Up to `count` nodes in up to 3 roots, with varied panel sizes.
    mutating func forest(count: Int) -> [LayoutNode] {
        var nodes: [LayoutNode] = []
        for index in 0 ..< count {
            let parent = index < 3 || next(5) == 0 ? nil : nodes[next(nodes.count)].id
            let size = CGSize(width: CGFloat(240 + next(5) * 40), height: CGFloat(160 + next(6) * 40))
            nodes.append(LayoutNode(id: PanelID(), parent: parent, size: size))
        }
        return nodes
    }
}

func assertNoOverlap(_ frames: [PanelID: CGRect], file: StaticString = #filePath, line: UInt = #line) {
    let rects = Array(frames.values)
    for (index, rect) in rects.enumerated() {
        for other in rects[(index + 1)...] where rect.intersects(other) {
            XCTFail("\(rect) overlaps \(other)", file: file, line: line)
            return
        }
    }
}
