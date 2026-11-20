@testable import Arbor
import FileOpsKit
import XCTest

@MainActor
final class PanelContextMenuTests: XCTestCase {
    private var folder: URL!
    private var panel: FolderPanelController!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelContextMenuTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Sub"),
            withIntermediateDirectories: true
        )
        try Data().write(to: folder.appendingPathComponent("file.txt"))
        panel = FolderPanelController(url: folder, frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        panel.reload()
        let deadline = Date().addingTimeInterval(5)
        while panel.items.count < 2, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func menu(selecting names: Set<String>) -> NSMenu {
        panel.select(names: names)
        let menu = panel.makeContextMenu()
        panel.menuNeedsUpdate(menu)
        return menu
    }

    private func firstTag(in menu: NSMenu) throws -> NSMenuItem {
        let tags = try XCTUnwrap(menu.items.first { $0.submenu != nil }?.submenu)
        return try XCTUnwrap(tags.items.first)
    }

    func testTogglingATagWritesItAndChecksIt() throws {
        let tag = try firstTag(in: menu(selecting: ["file.txt"]))
        XCTAssertEqual(tag.state, .off)
        _ = panel.perform(tag.action, with: tag)
        let name = try XCTUnwrap(tag.representedObject as? String)
        XCTAssertEqual(try FinderTags.tags(of: folder.appendingPathComponent("file.txt")), [name])
        XCTAssertEqual(try firstTag(in: menu(selecting: ["file.txt"])).state, .on)
    }

    func testAddToFavoritesIsOfferedForFoldersOnly() {
        XCTAssertFalse(menu(selecting: ["file.txt"]).items
            .contains { $0.title == String(localized: "Add to Favorites") })
        var added: [URL] = []
        panel.onAddFavorites = { added = $0 }
        let favorite = menu(selecting: ["Sub", "file.txt"]).items
            .first { $0.title == String(localized: "Add to Favorites") }
        XCTAssertNotNil(favorite)
        _ = panel.perform(favorite?.action, with: favorite)
        XCTAssertEqual(added.map(\.lastPathComponent), ["Sub"])
    }
}
