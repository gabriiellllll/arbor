@testable import CanvasKit
import XCTest

final class BackgroundPatternTests: XCTestCase {
    func testSpacingIsBaseAtFullZoom() {
        XCTAssertEqual(BackgroundPattern.spacing(forScale: 1), BackgroundPattern.baseSpacing)
    }

    func testSpacingDoublesUntilReadableOnScreen() {
        let spacing = BackgroundPattern.spacing(forScale: 0.1)
        XCTAssertGreaterThanOrEqual(spacing * 0.1, BackgroundPattern.minimumScreenSpacing)
        XCTAssertLessThan(spacing / 2 * 0.1, BackgroundPattern.minimumScreenSpacing)
        XCTAssertEqual(spacing.truncatingRemainder(dividingBy: BackgroundPattern.baseSpacing), 0)
    }

    func testPositionsAreMultiplesOfSpacingInsideRange() {
        XCTAssertEqual(BackgroundPattern.positions(from: -30, to: 50, spacing: 24), [-24, 0, 24, 48])
        XCTAssertEqual(BackgroundPattern.positions(from: 1, to: 23, spacing: 24), [])
    }

    func testAllStylesAreListed() {
        XCTAssertEqual(CanvasBackground.allCases, [.dots, .grid, .crosses, .plain])
    }
}
