@testable import CanvasKit
import XCTest

final class ZoomTests: XCTestCase {
    func testClampedKeepsScaleInRange() {
        XCTAssertEqual(Zoom.clamped(0.01), Zoom.minimum)
        XCTAssertEqual(Zoom.clamped(10), Zoom.maximum)
        XCTAssertEqual(Zoom.clamped(1.3), 1.3)
    }

    func testStepInGoesToNextLevel() {
        XCTAssertEqual(Zoom.stepIn(from: 1), 1.1)
        XCTAssertEqual(Zoom.stepIn(from: 1.05), 1.1)
        XCTAssertEqual(Zoom.stepIn(from: Zoom.maximum), Zoom.maximum)
    }

    func testStepOutGoesToPreviousLevel() {
        XCTAssertEqual(Zoom.stepOut(from: 1), 0.9)
        XCTAssertEqual(Zoom.stepOut(from: 0.95), 0.9)
        XCTAssertEqual(Zoom.stepOut(from: Zoom.minimum), Zoom.minimum)
    }

    func testStepsAreSortedAndWithinRange() {
        XCTAssertEqual(Zoom.steps, Zoom.steps.sorted())
        XCTAssertEqual(Zoom.steps.first, Zoom.minimum)
        XCTAssertEqual(Zoom.steps.last, Zoom.maximum)
    }
}
