@testable import CanvasKit
import XCTest

final class RevealTests: XCTestCase {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testAlreadyVisibleTargetDoesNotMove() {
        let target = CGRect(x: 100, y: 100, width: 200, height: 200)
        XCTAssertEqual(Reveal.origin(revealing: target, in: visible, margin: 40), visible.origin)
    }

    func testTargetOnTheRightScrollsJustEnough() {
        let target = CGRect(x: 1100, y: 100, width: 200, height: 200)
        XCTAssertEqual(Reveal.origin(revealing: target, in: visible, margin: 40), CGPoint(x: 340, y: 0))
    }

    func testTargetAboveAndLeftScrollsToItsTopLeft() {
        let target = CGRect(x: -500, y: -300, width: 100, height: 100)
        XCTAssertEqual(Reveal.origin(revealing: target, in: visible, margin: 40), CGPoint(x: -540, y: -340))
    }

    func testTargetLargerThanVisibleAlignsTopLeft() {
        let target = CGRect(x: 2000, y: 2000, width: 3000, height: 3000)
        XCTAssertEqual(Reveal.origin(revealing: target, in: visible, margin: 40), CGPoint(x: 1960, y: 1960))
    }
}
