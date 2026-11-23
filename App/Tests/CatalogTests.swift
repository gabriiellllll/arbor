@testable import Arbor
import IndexKit
import XCTest

/// Panels of a disk that is not plugged in, from the catalog. The "disk" is a temporary folder
/// Root/{Big/data.bin, Small/} that is moved away after indexing.
@MainActor
final class CatalogTests: XCTestCase {
    private var folder: URL!
    private var away: URL!
    private var defaults: UserDefaults!
    private let suite = "CatalogTests"

    override func setUp() async throws {
        try await super.setUp()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("CatalogTests-\(UUID().uuidString)")
        folder = base.appendingPathComponent("Root", isDirectory: true)
        away = base.appendingPathComponent("Unplugged", isDirectory: true)
        for path in ["Big", "Small"] {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent(path), withIntermediateDirectories: true
            )
        }
        try Data(count: 3000).write(to: folder.appendingPathComponent("Big/data.bin"))
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(condition(), message)
    }

    func testPanelOfAnUnpluggedDiskShowsItsCatalogGreyedOut() async throws {
        let service = try IndexService.openForUITests(fixture: folder)
        let path = FolderWatcher.canonicalPath(of: folder)
        service.start()
        try await waitUntil("indexed") { service.sizes(ofFolder: path)["Big"] == 3000 }
        service.stop()
        try FileManager.default.moveItem(at: folder, to: away)

        let canvas = CanvasViewController(defaults: defaults)
        canvas.loadView()
        canvas.index = service
        canvas.openRoot(folder)
        let panel = try XCTUnwrap(canvas.panels.values.first)
        try await waitUntil("shown from the catalog") { panel.offlineDisk != nil }
        XCTAssertEqual(panel.items.map(\.name), ["Big", "Small"])
        XCTAssertEqual(panel.offlineDisk, "Root")
        XCTAssertFalse(panel.offlineBanner.isHidden)
        XCTAssertEqual(panel.offlineBanner.stringValue, String(localized: "Plug in “Root” to open this folder."))

        try FileManager.default.moveItem(at: away, to: folder)
        canvas.indexChanged()
        try await waitUntil("read from disk again") { panel.offlineDisk == nil && panel.items.count == 2 }
        XCTAssertTrue(panel.offlineBanner.isHidden)
    }

    func testSearchResultOnAnUnpluggedDiskOpensItsCatalogChain() async throws {
        let service = try IndexService.openForUITests(fixture: folder)
        let path = FolderWatcher.canonicalPath(of: folder)
        service.start()
        try await waitUntil("indexed") { service.sizes(ofFolder: path)["Big"] == 3000 }
        service.stop()
        try FileManager.default.moveItem(at: folder, to: away)

        let canvas = CanvasViewController(defaults: defaults)
        canvas.loadView()
        canvas.index = service
        canvas.reveal(path: path + "/Big/data.bin")
        try await waitUntil("chain opened from the catalog") {
            canvas.panels.values.first { $0.title == "Big" }?.selectedItems.map(\.name) == ["data.bin"]
        }
        XCTAssertTrue(canvas.panels.values.allSatisfy { $0.offlineDisk == "Root" })
    }
}

/// Cataloged disks in the sidebar.
@MainActor
final class SidebarCatalogTests: XCTestCase {
    func testUnpluggedDisksAreListedWithTheirCommands() throws {
        let store = try IndexStore.inMemory()
        let gone = "/Volumes/Unplugged-\(UUID().uuidString)"
        _ = try store.addRoot(path: gone, exclusions: [])
        try store.updateVolumes([MountedVolume(path: gone, uuid: "U1")])
        let index = IndexService(store: store)

        let sidebar = try SidebarViewController(database: AppDatabase.inMemory())
        sidebar.loadView()
        sidebar.index = index
        let places = sidebar.section(.locations)?.children.compactMap { node -> Place? in
            if case let .place(place) = node.kind {
                return place
            }
            return nil
        } ?? []
        let disk = try XCTUnwrap(places.first { $0.kind == .offlineDisk })
        XCTAssertEqual(disk.url.path, gone)

        let menu = NSMenu()
        sidebar.addCatalogItems(for: disk, to: menu)
        XCTAssertEqual(
            menu.items.map(\.title).filter { !$0.isEmpty },
            [String(localized: "Remove from Catalog…"), String(localized: "Disk Details…")]
        )
        let volume = Place(url: URL(fileURLWithPath: "/Volumes/Other"), name: "Other", kind: .volume)
        let other = NSMenu()
        sidebar.addCatalogItems(for: volume, to: other)
        XCTAssertTrue(other.items.contains { $0.title == String(localized: "Add to Catalog") })
    }
}
