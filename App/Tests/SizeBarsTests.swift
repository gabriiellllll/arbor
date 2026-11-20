@testable import Arbor
import XCTest

final class SizeBarsTests: XCTestCase {
    func testLargestItemFillsTheRow() {
        XCTAssertEqual(SizeBars.fractions([50, 200, 100]), [0.25, 1, 0.5])
    }

    func testNothingWithASizeDrawsNoBars() {
        XCTAssertEqual(SizeBars.fractions([0, 0]), [0, 0])
        XCTAssertEqual(SizeBars.fractions([]), [])
    }

    func testNegativeSizesCountAsZero() {
        XCTAssertEqual(SizeBars.fractions([-5, 10]), [0, 1])
    }
}
