@testable import IndexKit
import XCTest

final class IndexStoreTests: XCTestCase {
    private var store: IndexStore!

    override func setUpWithError() throws {
        store = try IndexStore.inMemory()
    }

    private func entry(_ name: String, _ kind: DirectoryEntry.Kind, size: Int64 = 0) -> DirectoryEntry {
        DirectoryEntry(
            name: name, kind: kind, size: size, allocatedSize: size, itemCount: nil,
            created: Date(timeIntervalSince1970: 1), modified: Date(timeIntervalSince1970: 2), fileID: 1,
            isHidden: false
        )
    }

    func testAddingARootCreatesItsItem() throws {
        let root = try store.addRoot(path: "/data", exclusions: ["/data/skip"])
        XCTAssertEqual(try store.roots(), [root])
        XCTAssertEqual(root.exclusions, ["/data/skip"])
        XCTAssertEqual(try store.itemID(forPath: "/data"), root.itemID)
        XCTAssertNil(root.scannedAt)
    }

    func testAddingTheSameRootTwiceKeepsOne() throws {
        _ = try store.addRoot(path: "/data", exclusions: [])
        _ = try store.addRoot(path: "/data", exclusions: ["/data/x"])
        XCTAssertEqual(try store.roots().count, 1)
        XCTAssertEqual(try store.roots().first?.exclusions, ["/data/x"])
    }

    func testPathsResolveThroughTheirComponents() throws {
        let root = try store.addRoot(path: "/data", exclusions: [])
        let ids = try store.insertChildren(
            [entry("docs", .directory), entry("a.txt", .file, size: 5)], parent: root.itemID, rootID: root.id, depth: 1
        )
        _ = try store.insertChildren([entry("b.txt", .file, size: 7)], parent: ids[0], rootID: root.id, depth: 2)
        XCTAssertEqual(try store.itemID(forPath: "/data/docs"), ids[0])
        XCTAssertNotNil(try store.itemID(forPath: "/data/docs/b.txt"))
        XCTAssertNil(try store.itemID(forPath: "/data/missing"))
        XCTAssertNil(try store.itemID(forPath: "/elsewhere"), "outside every root")
        XCTAssertEqual(try store.children(of: ids[0]).map(\.name), ["b.txt"])
    }

    func testTheDeepestRootContainingAPathWins() throws {
        let outer = try store.addRoot(path: "/data", exclusions: [])
        let inner = try store.addRoot(path: "/data/inner", exclusions: [])
        XCTAssertEqual(try store.root(containing: "/data/inner/x")?.id, inner.id)
        XCTAssertEqual(try store.root(containing: "/data/x")?.id, outer.id)
        XCTAssertNil(try store.root(containing: "/database"), "a prefix of the name is not a parent")
    }

    func testRemovingARootRemovesItsItems() throws {
        let root = try store.addRoot(path: "/data", exclusions: [])
        _ = try store.insertChildren([entry("a.txt", .file)], parent: root.itemID, rootID: root.id, depth: 1)
        try store.removeRoot(root.id)
        XCTAssertEqual(try store.roots(), [])
        XCTAssertEqual(try store.itemCount(), 0)
    }

    func testDeletingAFolderDeletesItsSubtree() throws {
        let root = try store.addRoot(path: "/data", exclusions: [])
        let docs = try store
            .insertChildren([entry("docs", .directory)], parent: root.itemID, rootID: root.id, depth: 1)[0]
        _ = try store.insertChildren([entry("b.txt", .file)], parent: docs, rootID: root.id, depth: 2)
        try store.deleteItem(docs)
        XCTAssertEqual(try store.itemCount(), 1, "only the root item remains")
    }

    func testScanStateIsRecorded() throws {
        let root = try store.addRoot(path: "/data", exclusions: [])
        try store.markScanned(root.id, eventID: 42, volumeUUID: "UUID-1")
        let updated = try XCTUnwrap(store.roots().first)
        XCTAssertNotNil(updated.scannedAt)
        XCTAssertEqual(updated.lastEventID, 42)
        XCTAssertEqual(updated.volumeUUID, "UUID-1")
        try store.setLastEventID(root.id, 50)
        XCTAssertEqual(try store.roots().first?.lastEventID, 50)
    }
}
