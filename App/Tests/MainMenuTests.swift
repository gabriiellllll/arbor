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
