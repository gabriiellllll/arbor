@testable import IndexKit
import XCTest

/// Applies simulated FSEvents changes and checks the index matches the disk.
/// Starts from Root/{a.txt (10), docs/{b.txt (20), deep/{c.txt (30)}}, skip/ (excluded)}.
final class IndexUpdaterTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var store: IndexStore!
    private var root: IndexRoot!
    private var updater: IndexUpdater!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        try temp.file("a.txt", size: 10)
        try temp.file("docs/b.txt", size: 20)
        try temp.file("docs/deep/c.txt", size: 30)
        try temp.directory("skip")
        store = try IndexStore.inMemory()
        root = try store.addRoot(path: temp.url.path, exclusions: [path("skip")])
        try IndexScanner(store: store).scan(root)
        updater = IndexUpdater(store: store)
    }

    override func tearDown() {
        temp.remove()
    }

    private func path(_ relative: String) -> String {
        relative.isEmpty ? temp.url.path : temp.url.appendingPathComponent(relative).path
    }

    private func total(_ relative: String) throws -> Int64? {
        try store.itemID(forPath: path(relative)).flatMap { try store.item($0)?.totalSize }
    }

    private func changed(_ relative: String, rescan: Bool = false) throws -> Set<String> {
        try updater.apply([FolderChange(path: path(relative), mustRescanSubfolders: rescan)])
    }

    /// The index after the update equals a fresh scan of the disk.
    private func assertMatchesFreshScan(file: StaticString = #filePath, line: UInt = #line) throws {
        let fresh = try IndexStore.inMemory()
        let freshRoot = try fresh.addRoot(path: root.path, exclusions: root.exclusions)
        try IndexScanner(store: fresh).scan(freshRoot)
        XCTAssertEqual(try store.itemCount(), try fresh.itemCount(), "item count", file: file, line: line)
        XCTAssertEqual(
            try store.item(root.itemID)?.totalSize, try fresh.item(freshRoot.itemID)?.totalSize, "root total",
            file: file, line: line
        )
    }

    func testNewFileIsAddedAndTotalsGrowUpTheChain() throws {
        try temp.file("docs/new.txt", size: 7)
        let affected = try changed("docs")
        XCTAssertEqual(try total("docs/new.txt"), 7)
        XCTAssertEqual(try total("docs"), 57)
        XCTAssertEqual(try total(""), 67)
        XCTAssertEqual(affected, [path("docs")])
        try assertMatchesFreshScan()
    }

    func testRemovedFileIsDeleted() throws {
        try FileManager.default.removeItem(atPath: path("docs/b.txt"))
        _ = try changed("docs")
        XCTAssertNil(try store.itemID(forPath: path("docs/b.txt")))
        XCTAssertEqual(try total(""), 40)
        try assertMatchesFreshScan()
    }

    func testResizedFileUpdatesTotals() throws {
        try temp.file("docs/deep/c.txt", size: 3)
        _ = try changed("docs/deep")
        XCTAssertEqual(try total("docs"), 23)
        XCTAssertEqual(try total(""), 33)
        try assertMatchesFreshScan()
    }

    func testNewFolderIsIndexedWithItsContents() throws {
        try temp.file("photos/2026/p.jpg", size: 100)
        _ = try changed("")
        XCTAssertEqual(try total("photos"), 100)
        XCTAssertEqual(try total("photos/2026/p.jpg"), 100)
        try assertMatchesFreshScan()
    }

    func testDeletedFolderReportedOnItselfRefreshesTheParent() throws {
        try FileManager.default.removeItem(atPath: path("docs"))
        _ = try changed("docs/deep")
        XCTAssertNil(try store.itemID(forPath: path("docs")))
        XCTAssertEqual(try total(""), 10)
        try assertMatchesFreshScan()
    }

    func testFileReplacedByFolderChangesKind() throws {
        try FileManager.default.removeItem(atPath: path("a.txt"))
        try temp.file("a.txt/inside", size: 4)
        _ = try changed("")
        XCTAssertEqual(try store.item(XCTUnwrap(store.itemID(forPath: path("a.txt"))))?.isDirectory, true)
        XCTAssertEqual(try total("a.txt"), 4)
        try assertMatchesFreshScan()
    }

    func testMustRescanSubfoldersRebuildsTheSubtree() throws {
        try temp.file("docs/deep/more/d.txt", size: 9)
        try FileManager.default.removeItem(atPath: path("docs/b.txt"))
        _ = try changed("docs", rescan: true)
        XCTAssertEqual(try total("docs"), 39)
        try assertMatchesFreshScan()
    }

    func testRefreshAllCatchesUpEverywhereAndKeepsUnchangedItems() throws {
        let unchanged = try store.itemID(forPath: path("docs/b.txt"))
        try temp.file("docs/deep/c.txt", size: 31)
        try temp.file("docs/deep/more/d.txt", size: 4)
        try FileManager.default.removeItem(atPath: path("a.txt"))
        try updater.refreshAll(root)
        XCTAssertEqual(try total("docs/deep"), 35)
        XCTAssertEqual(try total(""), 55)
        XCTAssertNil(try store.itemID(forPath: path("a.txt")))
        XCTAssertEqual(try store.itemID(forPath: path("docs/b.txt")), unchanged, "unchanged items keep their row")
        try assertMatchesFreshScan()
    }

    func testChangesOutsideTheIndexAreIgnored() throws {
        try temp.file("skip/big.bin", size: 1000)
        XCTAssertEqual(try changed("skip"), [])
        XCTAssertEqual(try updater.apply([FolderChange(path: "/nowhere/else", mustRescanSubfolders: false)]), [])
        XCTAssertEqual(try total(""), 60)
    }
}
