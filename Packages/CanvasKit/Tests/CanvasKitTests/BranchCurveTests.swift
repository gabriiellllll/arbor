@testable import CanvasKit
import XCTest

final class BranchCurveTests: XCTestCase {
    func testCurveStartsAndEndsAtGivenPoints() {
        let curve = BranchCurve(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100))
        XCTAssertEqual(curve.start, CGPoint(x: 0, y: 0))
        XCTAssertEqual(curve.end, CGPoint(x: 200, y: 100))
    }

    func testTangentsAreHorizontalAtBothEnds() {
        let curve = BranchCurve(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100))
        XCTAssertEqual(curve.control1.y, curve.start.y)
        XCTAssertEqual(curve.control2.y, curve.end.y)
        XCTAssertEqual(curve.control1, CGPoint(x: 100, y: 0))
        XCTAssertEqual(curve.control2, CGPoint(x: 100, y: 100))
    }

    func testShortBranchesKeepAMinimumBend() {
        let curve = BranchCurve(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 300))
        XCTAssertEqual(curve.control1.x, BranchCurve.minimumBend)
        XCTAssertEqual(curve.control2.x, 10 - BranchCurve.minimumBend)
    }

    func testPathBoundsContainEndpoints() {
        let curve = BranchCurve(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 200, y: 100))
        let bounds = curve.path.boundingBoxOfPath
        XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(curve.start))
        XCTAssertTrue(bounds.insetBy(dx: -0.01, dy: -0.01).contains(curve.end))
    }
}
