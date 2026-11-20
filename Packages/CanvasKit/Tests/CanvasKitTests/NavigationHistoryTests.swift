@testable import CanvasKit
import XCTest

final class NavigationHistoryTests: XCTestCase {
    func testStartsEmpty() {
        let history = NavigationHistory<String>()
        XCTAssertNil(history.current)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func testBackAndForwardWalkTheVisits() {
        var history = NavigationHistory<String>()
        ["a", "b", "c"].forEach { history.visit($0) }
        XCTAssertEqual(history.back(), "b")
        XCTAssertEqual(history.back(), "a")
        XCTAssertNil(history.back())
        XCTAssertEqual(history.current, "a")
        XCTAssertEqual(history.forward(), "b")
        XCTAssertTrue(history.canGoForward)
    }

    func testVisitingAfterGoingBackDropsTheForwardEntries() {
        var history = NavigationHistory<String>()
        ["a", "b", "c"].forEach { history.visit($0) }
        _ = history.back()
        history.visit("d")
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.entries, ["a", "b", "d"])
    }

    func testRepeatedVisitIsIgnored() {
        var history = NavigationHistory<String>()
        history.visit("a")
        history.visit("a")
        XCTAssertEqual(history.entries, ["a"])
    }

    func testOldestEntriesAreDroppedPastTheLimit() {
        var history = NavigationHistory<Int>(limit: 3)
        (1 ... 5).forEach { history.visit($0) }
        XCTAssertEqual(history.entries, [3, 4, 5])
        XCTAssertEqual(history.current, 5)
        XCTAssertEqual(history.back(), 4)
    }
}
