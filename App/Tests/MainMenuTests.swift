@testable import Arbor
import CanvasKit
import XCTest

@MainActor
final class MainMenuTests: XCTestCase {
    func testQuitItemUsesCommandQ() throws {
        let appMenu = try XCTUnwrap(MainMenu.make().items.first?.submenu)
        let quit = try XCTUnwrap(appMenu.items.first { $0.action == #selector(NSApplication.terminate(_:)) })
        XCTAssertEqual(quit.keyEquivalent, "q")
        XCTAssertEqual(quit.keyEquivalentModifierMask, .command)
    }

    func testConnectToServerUsesCommandK() throws {
        let item = try XCTUnwrap(MainMenu.fileMenu().items.first {
            $0.action == #selector(MainWindowController.connectToServer(_:))
        })
        XCTAssertEqual(item.keyEquivalent, "k")
        XCTAssertEqual(item.keyEquivalentModifierMask, .command)
    }
}

@MainActor
final class ViewMenuTests: XCTestCase {
    func testZoomCommandsHaveStandardShortcuts() {
        let menu = MainMenu.viewMenu()
        let shortcuts = Dictionary(menu.items.compactMap { item in
            item.action.map { ($0, item.keyEquivalent) }
        }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(shortcuts[#selector(MainWindowController.zoomIn(_:))], "+")
        XCTAssertEqual(shortcuts[#selector(MainWindowController.zoomOut(_:))], "-")
        XCTAssertEqual(shortcuts[#selector(MainWindowController.resetZoom(_:))], "0")
    }

    func testLayoutMenuHasNumberShortcutsInOrder() {
        let menu = MainMenu.layoutMenu()
        XCTAssertEqual(menu.items.map(\.tag), Array(CanvasLayout.allCases.indices))
        XCTAssertEqual(menu.items.map(\.keyEquivalent), ["1", "2", "3", "4"])
    }

    func testBackgroundMenuListsEveryStyleInOrder() {
        let menu = MainMenu.backgroundMenu()
        XCTAssertEqual(menu.items.map(\.tag), Array(0 ..< 4))
    }
}
