@testable import Arbor
import IndexKit
import XCTest

/// Folder sizes from the index, in panels and through the app's index service.
@MainActor
final class IndexSizesTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexSizesTests-\(UUID().uuidString)/Root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Big"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Small"),
            withIntermediateDirectories: true
        )
        try Data(count: 3000).write(to: folder.appendingPathComponent("Big/data.bin"))
        try Data(count: 10).write(to: folder.appendingPathComponent("Small/tiny.txt"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(condition(), message)
    }

    private func sizeText(_ panel: FolderPanelController, _ name: String) -> String? {
        guard let row = panel.rowIndex(forName: name) else { return nil }
        let column = panel.tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(FolderSortKey.size.rawValue))
        let cell = panel.tableView(panel.tableView, viewFor: panel.tableView.tableColumns[column], row: row)
        return (cell as? NSTableCellView)?.textField?.stringValue
    }

    func testPanelsShowAndSortByIndexedFolderSizes() async throws {
        var sizes: [String: Int64] = ["Big": 3000, "Small": 10]
        let panel = FolderPanelController(url: folder, frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        panel.sizeLookup = { _ in sizes }
        panel.reload()
        try await waitUntil("panel loads") { panel.items.count == 2 }
        XCTAssertEqual(sizeText(panel, "Big"), ByteCountFormatter.string(fromByteCount: 3000, countStyle: .file))

        panel.tableView.sortDescriptors = [NSSortDescriptor(key: FolderSortKey.size.rawValue, ascending: false)]
        XCTAssertEqual(panel.items.map(\.name), ["Big", "Small"])

        sizes = ["Big": 1, "Small": 10]
        panel.refreshSizes()
        XCTAssertEqual(panel.items.map(\.name), ["Small", "Big"], "re-sorted when the index changes")
    }

    func testSizeBarsFollowSizes() async throws {
        let panel = FolderPanelController(url: folder, frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        panel.sizeLookup = { _ in ["Big": 3000, "Small": 750] }
        panel.reload()
        try await waitUntil("panel loads") { panel.items.count == 2 }
        func bar(_ name: String) -> Double? {
            panel.rowIndex(forName: name).flatMap {
                (panel.tableView(panel.tableView, rowViewForRow: $0) as? TintedRowView)?.sizeFraction
            }
        }
        XCTAssertEqual(bar("Big"), 0, "no bars until shown")
        panel.showsSizeBars = true
        XCTAssertEqual(bar("Big"), 1)
        XCTAssertEqual(bar("Small"), 0.25)
    }

    func testFoldersWithoutIndexedSizesShowDashes() async throws {
        let panel = FolderPanelController(url: folder, frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        panel.reload()
        try await waitUntil("panel loads") { panel.items.count == 2 }
        XCTAssertEqual(sizeText(panel, "Big"), "--")
    }

    func testIndexServiceComputesFolderSizes() async throws {
        let service = try IndexService.openForUITests(fixture: folder)
        service.start()
        let path = FolderWatcher.canonicalPath(of: folder)
        try await waitUntil("index ready") { service.sizes(ofFolder: path)["Big"] != nil }
        XCTAssertEqual(service.sizes(ofFolder: path)["Big"], 3000)
        XCTAssertEqual(service.sizes(ofFolder: path)["Small"], 10)
        service.stop()
    }
}
