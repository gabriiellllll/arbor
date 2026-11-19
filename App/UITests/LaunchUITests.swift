import XCTest

final class LaunchUITests: XCTestCase {
    @MainActor
    func testLaunchShowsMainWindow() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows["main"].waitForExistence(timeout: 10))
    }
}
