@testable import CanvasKit
import XCTest

@MainActor
final class BranchPaletteTests: XCTestCase {
    func testFirstColorWhenNoneUsed() {
        XCTAssertEqual(BranchPalette.nextIndex(used: []), 0)
    }

    func testPicksLowestUnusedIndex() {
        XCTAssertEqual(BranchPalette.nextIndex(used: [0, 1, 3]), 2)
    }

    func testPicksLeastUsedOnceAllAreTaken() {
        let used = Array(BranchPalette.colors.indices) + [0, 1]
        XCTAssertEqual(BranchPalette.nextIndex(used: used), 2)
    }

    func testCountMatchesColors() {
        XCTAssertEqual(BranchPalette.colors.count, BranchPalette.count)
    }

    func testColorWrapsAround() {
        XCTAssertEqual(BranchPalette.color(at: BranchPalette.colors.count), BranchPalette.colors[0])
        XCTAssertEqual(BranchPalette.color(at: -1), BranchPalette.colors.last)
    }
}
