@testable import IndexKit
import XCTest

/// Root/{a.txt (10), .hidden (5), docs/{b.txt (20), deep/{c.txt (30)}}, skip/{x.txt (100)}}
final class IndexScannerTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var store: IndexStore!
    private var root: IndexRoot!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        try temp.file("a.txt", size: 10)
        try temp.file(".hidden", size: 5)
        try temp.file("docs/b.txt", size: 20)
        try temp.file("docs/deep/c.txt", size: 30)
        try temp.file("skip/x.txt", size: 100)
        store = try IndexStore.inMemory()
        root = try store.addRoot(path: temp.url.path, exclusions: [temp.url.appendingPathComponent("skip").path])
    }

    override func tearDown() {
        temp.remove()
    }

    private func item(_ path: String) throws -> IndexedItem {
        let id = try XCTUnwrap(store.itemID(forPath: temp.url.appendingPathComponent(path).path), "\(path) not indexed")
        return try XCTUnwrap(store.item(id))
    }

    func testIndexesEverythingButExclusions() throws {
        let summary = try IndexScanner(store: store).scan(root)
        XCTAssertEqual(summary.items, 6)
        XCTAssertNoThrow(try item("docs/deep/c.txt"))
        XCTAssertNoThrow(try item(".hidden"))
        XCTAssertNil(try store.itemID(forPath: temp.url.appendingPathComponent("skip").path))
    }

    func testFolderSizesAddUpFromTheBottom() throws {
        _ = try IndexScanner(store: store).scan(root)
        XCTAssertEqual(try item("docs/deep").totalSize, 30)
        XCTAssertEqual(try item("docs").totalSize, 50)
        XCTAssertEqual(try store.item(root.itemID)?.totalSize, 65)
        XCTAssertEqual(try item("docs").descendants, 3)
        XCTAssertEqual(try store.item(root.itemID)?.descendants, 6)
        XCTAssertGreaterThanOrEqual(try item("docs").totalAllocated, 50)
        XCTAssertEqual(try store.childSizes(ofFolder: temp.url.path)["docs"], 50)
    }

    func testSymlinksAreNotFollowed() throws {
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("link"), withDestinationURL: temp.url.appendingPathComponent("docs")
        )
        _ = try IndexScanner(store: store).scan(root)
        XCTAssertNil(try store.itemID(forPath: temp.url.appendingPathComponent("link/b.txt").path))
        XCTAssertEqual(try store.item(root.itemID)?.totalSize, try 65 + item("link").size)
    }

    func testUnreadableFoldersAreReportedAndSkipped() throws {
        let locked = try temp.directory("locked")
        try temp.file("locked/secret", size: 1)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let summary = try IndexScanner(store: store).scan(root)
        XCTAssertEqual(summary.unreadable, [locked.path])
        XCTAssertNoThrow(try item("locked"))
        XCTAssertEqual(try store.item(root.itemID)?.totalSize, 65)
    }

    func testRescanReplacesThePreviousState() throws {
        _ = try IndexScanner(store: store).scan(root)
        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("docs"))
        try temp.file("new.txt", size: 1)
        _ = try IndexScanner(store: store).scan(root)
        XCTAssertNil(try store.itemID(forPath: temp.url.appendingPathComponent("docs").path))
        XCTAssertEqual(try store.item(root.itemID)?.totalSize, 16)
        XCTAssertEqual(try store.itemCount(), 4, "root, a.txt, .hidden, new.txt")
    }

    func testCancelStopsTheScan() throws {
        let control = ScanControl()
        control.cancel()
        XCTAssertThrowsError(try IndexScanner(store: store).scan(root, control: control)) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testProgressCountsItems() throws {
        let counter = Counter()
        _ = try IndexScanner(store: store).scan(root, progress: { counter.set($0) })
        XCTAssertEqual(counter.value, 6)
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0

    func set(_ value: Int) {
        lock.withLock { current = value }
    }

    var value: Int {
        lock.withLock { current }
    }
}
