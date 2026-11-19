import XCTest

/// Drives the canvas on a fixture folder tree the app creates in a temporary directory.
final class CanvasUITests: XCTestCase {
    private var app: XCUIApplication!

    @MainActor
    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["ARBOR_UI_TEST_FIXTURE"] = "1"
        app.launch()
    }

    @MainActor
    private func row(_ name: String, in panel: String) -> XCUIElement {
        app.tables["list.\(panel)"].staticTexts[name]
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testOpensFolderAsPanel() {
        XCTAssertTrue(app.groups["panel.Root"].waitForExistence(timeout: 10))
        XCTAssertTrue(row("Alpha", in: "Root").waitForExistence(timeout: 5))
        XCTAssertTrue(row("notes.txt", in: "Root").exists)
    }

    @MainActor
    func testSelectingFoldersOpensAndReplacesChildPanels() {
        XCTAssertTrue(row("Alpha", in: "Root").waitForExistence(timeout: 10))

        row("Alpha", in: "Root").click()
        XCTAssertTrue(app.groups["panel.Alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(row("Inner", in: "Alpha").waitForExistence(timeout: 5))
        attachScreenshot("child panel")

        row("Beta", in: "Root").click()
        XCTAssertTrue(app.groups["panel.Beta"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.groups["panel.Alpha"].exists, "selecting a sibling replaces the branch")

        XCUIElement.perform(withKeyModifiers: .command) {
            row("Alpha", in: "Root").click()
        }
        XCTAssertTrue(app.groups["panel.Alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.groups["panel.Beta"].exists, "⌘-click keeps the other branch")
        attachScreenshot("two branches")
    }

    @MainActor
    func testDeepNavigationKeepsTheChain() {
        XCTAssertTrue(row("Alpha", in: "Root").waitForExistence(timeout: 10))
        row("Alpha", in: "Root").click()
        XCTAssertTrue(row("Inner", in: "Alpha").waitForExistence(timeout: 5))
        row("Inner", in: "Alpha").click()
        XCTAssertTrue(app.groups["panel.Inner"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.groups["panel.Root"].exists)
        XCTAssertTrue(app.groups["panel.Alpha"].exists)
        attachScreenshot("deep chain")
    }
}
