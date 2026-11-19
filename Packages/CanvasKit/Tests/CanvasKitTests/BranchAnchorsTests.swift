@testable import CanvasKit
import XCTest

final class BranchAnchorsTests: XCTestCase {
    private let parent = CGRect(x: 0, y: 0, width: 300, height: 400)

    func testChildOnTheRightLinksRightEdgeToTitle() {
        let child = CGRect(x: 400, y: 50, width: 300, height: 400)
        let curve = BranchAnchors.curve(parent: parent, sourceY: 120, child: child)
        XCTAssertEqual(curve.start, CGPoint(x: 300, y: 120))
        XCTAssertEqual(curve.end, CGPoint(x: 400, y: 50 + PanelPlacement.titleOffset))
        XCTAssertGreaterThan(curve.control1.x, curve.start.x)
        XCTAssertLessThan(curve.control2.x, curve.end.x)
    }

    func testChildOnTheLeftLinksLeftEdges() {
        let child = CGRect(x: -500, y: 0, width: 300, height: 400)
        let curve = BranchAnchors.curve(parent: parent, sourceY: 120, child: child)
        XCTAssertEqual(curve.start, CGPoint(x: 0, y: 120))
        XCTAssertEqual(curve.end.x, -200)
        XCTAssertLessThan(curve.control1.x, curve.start.x)
    }

    func testChildRightBelowIsEnteredFromTheTopCenter() {
        // Slightly right of the parent, well below it: the vertical gap wins.
        let child = CGRect(x: 320, y: 500, width: 300, height: 400)
        let curve = BranchAnchors.curve(parent: parent, sourceY: 120, child: child)
        XCTAssertEqual(curve.start, CGPoint(x: 300, y: 120))
        XCTAssertEqual(curve.end, CGPoint(x: 470, y: 500))
        XCTAssertLessThan(curve.control2.y, curve.end.y, "arrives moving down")
    }

    func testChildDirectlyBelowIsEnteredNearItsTopRightCorner() {
        let child = CGRect(x: 0, y: 500, width: 300, height: 400)
        let curve = BranchAnchors.curve(parent: parent, sourceY: 120, child: child)
        XCTAssertEqual(curve.end, CGPoint(x: 300 - BranchAnchors.cornerInset, y: 500))
    }

    func testChildBelowAndLeftIsEnteredClearOfTheParent() {
        let child = CGRect(x: -100, y: 500, width: 600, height: 400)
        let curve = BranchAnchors.curve(parent: parent, sourceY: 120, child: child)
        XCTAssertEqual(curve.end.x, 300 + BranchCurve.minimumBend, "clear of the parent, not looping behind it")
    }

    func testChildAboveIsEnteredFromTheBottom() {
        let child = CGRect(x: 0, y: -600, width: 300, height: 400)
        let curve = BranchAnchors.curve(parent: parent, sourceY: 120, child: child)
        XCTAssertEqual(curve.end, CGPoint(x: 300 - BranchAnchors.cornerInset, y: -200))
        XCTAssertGreaterThan(curve.control2.y, curve.end.y, "arrives moving up")
    }

    func testDiagonalChildUsesTheWiderGap() {
        let child = CGRect(x: 800, y: 450, width: 300, height: 400)
        let curve = BranchAnchors.curve(parent: parent, sourceY: 120, child: child)
        XCTAssertEqual(curve.end.x, 800, "the horizontal gap (500) beats the vertical one (50)")
    }

    func testOverlappingPanelsFallBackToTheRight() {
        let child = CGRect(x: 100, y: 100, width: 300, height: 400)
        XCTAssertEqual(BranchAnchors.curve(parent: parent, sourceY: 120, child: child).start.x, 300)
    }
}
