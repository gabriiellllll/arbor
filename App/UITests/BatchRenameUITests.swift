import XCTest

/// Batch rename through the sheet, on the fixture tree, then undo.
final class BatchRenameUITests: XCTestCase {
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
    private func row(_ name: String) -> XCUIElement {
        app.tables["list.Root"].staticTexts[name]
    }

    @MainActor
    func testRenameTwoItemsWithATemplateThenUndo() {
        XCTAssertTrue(row("notes.txt").waitForExistence(timeout: 10))
        // The file first: selecting Beta opens its panel and may scroll Root aside.
        row("notes.txt").click()
        XCUIElement.perform(withKeyModifiers: .command) { row("Beta").click() }

        app.menuBars.menuBarItems["File"].click()
        app.menuBars.menuItems["Rename 2 Items…"].click()
        let template = app.textFields["renameTemplate"]
        XCTAssertTrue(template.waitForExistence(timeout: 5))
        template.click()
        template.typeKey("a", modifierFlags: .command)
        template.typeText("{n:2} {name}")
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.staticTexts["02 notes.txt"].waitForExistence(timeout: 5), "the preview shows new names")
        let attachment = XCTAttachment(screenshot: app.windows["main"].screenshot())
        attachment.name = "batch rename"
        attachment.lifetime = .keepAlways
        add(attachment)
        sheet.buttons["Rename"].click()

        XCTAssertTrue(row("01 Beta").waitForExistence(timeout: 5))
        XCTAssertTrue(row("02 notes.txt").waitForExistence(timeout: 5))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(row("notes.txt").waitForExistence(timeout: 5), "undo restores both names")
        XCTAssertTrue(row("Beta").waitForExistence(timeout: 5))
    }
}
