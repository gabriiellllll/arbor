import XCTest

/// The sidebar's Shared section. UI tests never browse or mount anything on the network: the
/// fixture remembers a share whose server does not exist.
final class SharedUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["ARBOR_UI_TEST_FIXTURE"] = "1"
        app.launch()
        XCTAssertTrue(app.groups["panel.Root"].waitForExistence(timeout: 10))
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testRememberedShareIsListedAndServersConnectByAddress() {
        let sidebar = app.outlines["sidebar"]
        let share = sidebar.staticTexts["Projects"]
        XCTAssertTrue(share.waitForExistence(timeout: 10), "the remembered share is listed")
        XCTAssertTrue(sidebar.staticTexts["Shared"].exists)

        app.typeKey("k", modifierFlags: .command)
        let address = app.textFields["serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.click()
        address.typeText("nas.local/Media")
        attachScreenshot("connect to server")
        app.buttons["Cancel"].click()
        XCTAssertTrue(address.waitForNonExistence(timeout: 5))

        share.rightClick()
        app.menuItems["Forget Share"].click()
        XCTAssertTrue(share.waitForNonExistence(timeout: 5), "the share is forgotten")
    }
}
