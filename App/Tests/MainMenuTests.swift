@testable import Arbor
import XCTest

@MainActor
final class MainMenuTests: XCTestCase {
    func testQuitItemUsesCommandQ() throws {
        let appMenu = try XCTUnwrap(MainMenu.make().items.first?.submenu)
        let quit = try XCTUnwrap(appMenu.items.first { $0.action == #selector(NSApplication.terminate(_:)) })
        XCTAssertEqual(quit.keyEquivalent, "q")
        XCTAssertEqual(quit.keyEquivalentModifierMask, .command)
    }
}

@MainActor
final class ViewMenuTests: XCTestCase {
    func testZoomCommandsHaveStandardShortcuts() {
        let menu = MainMenu.viewMenu()
        let shortcuts = Dictionary(uniqueKeysWithValues: menu.items.compactMap { item in
            item.action.map { ($0, item.keyEquivalent) }
        })
        XCTAssertEqual(shortcuts[#selector(MainWindowController.zoomIn(_:))], "+")
        XCTAssertEqual(shortcuts[#selector(MainWindowController.zoomOut(_:))], "-")
        XCTAssertEqual(shortcuts[#selector(MainWindowController.resetZoom(_:))], "0")
    }

    func testBackgroundMenuListsEveryStyleInOrder() {
        let menu = MainMenu.backgroundMenu()
        XCTAssertEqual(menu.items.map(\.tag), Array(0 ..< 4))
    }
}
