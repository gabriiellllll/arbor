@testable import CanvasKit
import XCTest

final class CompareLayoutTests: XCTestCase {
    func testHomologousPanelsShareARow() {
        let left = [CGSize(width: 300, height: 200), CGSize(width: 360, height: 300)]
        let right = [CGSize(width: 300, height: 250), CGSize(width: 300, height: 200), CGSize(width: 300, height: 200)]
        let frames = CompareLayout.frames(left: left, right: right, origin: CGPoint(x: 10, y: 20))
        XCTAssertEqual(frames.left.count, 2)
        XCTAssertEqual(frames.right.count, 3)
        XCTAssertEqual(frames.left[0].origin, CGPoint(x: 10, y: 20))
        for level in 0 ..< 2 {
            XCTAssertEqual(frames.left[level].minY, frames.right[level].minY)
        }
        XCTAssertEqual(frames.right[0].minX, 10 + 360 + CompareLayout.laneGap, "after the widest left panel")
        XCTAssertEqual(frames.left[1].minY, 20 + 250 + LayoutEngine.levelGap, "below the tallest panel of the row")
        let all = frames.left + frames.right
        for (index, rect) in all.enumerated() {
            for other in all[(index + 1)...] {
                XCTAssertFalse(rect.intersects(other))
            }
        }
    }

    func testEmptyChains() {
        let frames = CompareLayout.frames(left: [], right: [], origin: .zero)
        XCTAssertTrue(frames.left.isEmpty)
        XCTAssertTrue(frames.right.isEmpty)
    }
}
