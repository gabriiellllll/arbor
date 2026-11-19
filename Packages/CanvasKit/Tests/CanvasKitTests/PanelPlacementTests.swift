@testable import CanvasKit
import XCTest

final class PanelPlacementTests: XCTestCase {
    private let parent = CGRect(x: 0, y: 0, width: 300, height: 400)
    private let size = CGSize(width: 300, height: 400)

    func testChildGoesRightOfParentAlignedWithSourceRow() {
        let frame = PanelPlacement.childFrame(parent: parent, sourceY: 120, size: size, avoiding: [])
        XCTAssertEqual(frame.minX, parent.maxX + PanelPlacement.horizontalGap)
        XCTAssertEqual(frame.minY, 120 - PanelPlacement.titleOffset)
        XCTAssertEqual(frame.size, size)
    }

    func testChildMovesBelowOccupiedSpace() {
        let sibling = PanelPlacement.childFrame(parent: parent, sourceY: 120, size: size, avoiding: [])
        let frame = PanelPlacement.childFrame(parent: parent, sourceY: 140, size: size, avoiding: [parent, sibling])
        XCTAssertFalse(frame.intersects(sibling.insetBy(dx: -1, dy: -1)))
        XCTAssertEqual(frame.minY, sibling.maxY + PanelPlacement.verticalGap)
    }

    func testManyChildrenNeverOverlap() {
        var placed = [parent]
        for row in 0 ..< 20 {
            placed.append(PanelPlacement.childFrame(
                parent: parent, sourceY: CGFloat(row * 20), size: size, avoiding: placed
            ))
        }
        for (index, frame) in placed.enumerated() {
            for other in placed[(index + 1)...] {
                XCTAssertFalse(frame.intersects(other), "\(frame) overlaps \(other)")
            }
        }
    }
}
