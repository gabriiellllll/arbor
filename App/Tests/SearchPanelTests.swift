@testable import Arbor
import CanvasKit
import IndexKit
import XCTest

/// Search specs, and search panels on a canvas backed by an index of a temporary folder:
/// Root/{Big/data.bin, Small/tiny.txt}.
@MainActor
final class SearchPanelTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private let suite = "SearchPanelTests"

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("SearchPanelTests-\(UUID().uuidString)/Root", isDirectory: true)
        for path in ["Big", "Small"] {
            try FileManager.default.createDirectory(
                at: folder.appendingPathComponent(path), withIntermediateDirectories: true
            )
        }
        try Data(count: 3000).write(to: folder.appendingPathComponent("Big/data.bin"))
        try Data(count: 10).write(to: folder.appendingPathComponent("Small/tiny.txt"))
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

    func testSpecMapsFiltersToAQuery() throws {
        let now = Date(timeIntervalSince1970: 1_000_000_000)
        var spec = SearchSpec(text: "report", kind: .images, minSize: 1_000_000, age: .week, tag: "Red")
        let query = spec.query(now: now)
        XCTAssertEqual(query.text, "report")
        XCTAssertEqual(query.category, .images)
        XCTAssertNil(query.kind)
        XCTAssertEqual(query.minSize, 1_000_000)
        XCTAssertEqual(query.tag, "Red")
        let after = try XCTUnwrap(query.modifiedAfter)
        XCTAssertEqual(now.timeIntervalSince(after), 7 * 86400, accuracy: 3600)

        spec.kind = .folders
        XCTAssertEqual(spec.query().kind, .folders)
        XCTAssertNil(spec.query().category)
        XCTAssertEqual(spec.title, String(localized: "Search: report"))
        XCTAssertEqual(SearchSpec(tag: "Red").title, String(localized: "Tag: Red"))
    }

    func testNamesBelowABase() {
        XCTAssertEqual(CanvasViewController.names(of: "/a/b/c", below: "/a"), ["b", "c"])
        XCTAssertEqual(CanvasViewController.names(of: "/a/b", below: "/"), ["a", "b"])
        XCTAssertNil(CanvasViewController.names(of: "/ab/c", below: "/a"))
        XCTAssertNil(CanvasViewController.names(of: "/a", below: "/a"))
    }

    func testSearchPanelShowsResultsAndRevealsTheirFolderChain() async throws {
        let service = try IndexService.openForUITests(fixture: folder)
        service.start()
        defer { service.stop() }
        let canvas = CanvasViewController(defaults: defaults)
        canvas.loadView()
        canvas.view.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        canvas.index = service
        canvas.openRoot(folder)

        canvas.search(text: "tin")
        let search = try XCTUnwrap(canvas.searchPanels.values.first)
        XCTAssertEqual(canvas.activeSearch?.spec.text, "tin")
        // The index may still be scanning: results come with its change notifications.
        service.onChange = { _ in canvas.indexChanged() }
        try await waitUntil("result found") { search.results.map(\.name) == ["tiny.txt"] }

        canvas.search(text: "tiny")
        XCTAssertEqual(canvas.searchPanels.count, 1, "typing refines the active search")

        try canvas.reveal(path: XCTUnwrap(search.results.first).path)
        try await waitUntil("chain opens") {
            canvas.panels.values.first { $0.title == "Small" }?.selectedItems.map(\.name) == ["tiny.txt"]
        }
        XCTAssertEqual(canvas.panels.values.first { $0.title == "Root" }?.selectedItems.map(\.name), ["Small"])
        XCTAssertEqual(
            canvas.activePanel.flatMap { canvas.panels[$0] }?.title,
            "Small",
            "the result's folder is active"
        )

        let snapshot = canvas.snapshot()
        let restored = CanvasViewController(defaults: defaults)
        restored.loadView()
        restored.restore(snapshot)
        XCTAssertEqual(restored.searchPanels.values.map(\.spec), [SearchSpec(text: "tiny")])
    }

    func testSearchPanelShowsExcerptsOfDocumentText() async throws {
        try Data("Meeting in Zanzibar".utf8).write(to: folder.appendingPathComponent("Small/notes.md"))
        let service = try IndexService.openForUITests(fixture: folder)
        service.start()
        defer { service.stop() }
        let canvas = CanvasViewController(defaults: defaults)
        canvas.loadView()
        canvas.index = service
        service.onChange = { _ in canvas.indexChanged() }

        canvas.search(text: "zanzibar")
        let search = try XCTUnwrap(canvas.searchPanels.values.first)
        try await waitUntil("document text found") { search.results.first?.excerpt == "Meeting in Zanzibar" }
        let column = search.tableView.column(withIdentifier: NSUserInterfaceItemIdentifier("excerpt"))
        let cell = search.tableView.view(atColumn: column, row: 0, makeIfNecessary: true) as? NSTableCellView
        XCTAssertEqual(cell?.textField?.stringValue, "Meeting in Zanzibar")
    }
}

/// The sidebar's Tags section.
@MainActor
final class SidebarTagsTests: XCTestCase {
    func testTagsSectionListsIndexedTagsAndRefreshesOnlyWhenTheyChange() throws {
        let sidebar = try SidebarViewController(database: AppDatabase.inMemory())
        sidebar.loadView()
        XCTAssertNil(sidebar.section(.tags), "no section without tags")

        var tags = ["Red", "Work"]
        sidebar.tagNames = { tags }
        let section = try XCTUnwrap(sidebar.section(.tags))
        XCTAssertEqual(section.children.compactMap { node in
            if case let .tag(name) = node.kind {
                return name
            }
            return nil
        }, tags)

        sidebar.refreshTags()
        XCTAssertTrue(sidebar.section(.tags) === section, "unchanged tags keep the outline")
        tags = ["Red"]
        sidebar.refreshTags()
        XCTAssertEqual(sidebar.section(.tags)?.children.count, 1)
    }
}
