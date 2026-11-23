@testable import IndexKit
import XCTest

/// The coordinator on a real folder, an on-disk index and real FSEvents.
final class IndexCoordinatorTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        try temp.file("data/a.txt", size: 10)
        databaseURL = FileManager.default.temporaryDirectory.appendingPathComponent("index-\(UUID().uuidString).sqlite")
    }

    override func tearDown() {
        temp.remove()
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: databaseURL.path + suffix)
        }
    }

    private var dataPath: String {
        temp.url.appendingPathComponent("data").path
    }

    private static func total(_ store: IndexStore, _ path: String) -> Int64? {
        (try? store.itemID(forPath: path)).flatMap { (try? store.item($0))?.totalSize }
    }

    /// Starts a coordinator and waits until `condition` holds after a change notification.
    private func run(_ store: IndexStore, until condition: @escaping @Sendable () -> Bool) -> IndexCoordinator {
        let done = expectation(description: "condition met")
        done.assertForOverFulfill = false
        let coordinator = IndexCoordinator(store: store)
        coordinator.onChange = { _ in
            if condition() {
                done.fulfill()
            }
        }
        coordinator.start()
        wait(for: [done], timeout: 15)
        return coordinator
    }

    func testFirstStartScansThenFollowsChanges() throws {
        let store = try IndexStore.open(at: databaseURL)
        let path = dataPath
        _ = try store.addRoot(path: temp.url.path, exclusions: [])
        let coordinator = run(store) { Self.total(store, path) == 10 }
        XCTAssertNotNil(try store.roots().first?.scannedAt)

        let followed = expectation(description: "live change indexed")
        followed.assertForOverFulfill = false
        coordinator.onChange = { _ in
            if Self.total(store, path) == 15 {
                followed.fulfill()
            }
        }
        try temp.file("data/b.txt", size: 5)
        wait(for: [followed], timeout: 15)
        coordinator.stop()
    }

    func testDocumentTextIsReadAfterTheScanAndAfterChanges() throws {
        try Data("Quarterly zanzibar report".utf8).write(to: temp.url.appendingPathComponent("data/a.txt"))
        let store = try IndexStore.open(at: databaseURL)
        _ = try store.addRoot(path: temp.url.path, exclusions: [])
        let names = { @Sendable (text: String) in (try? store.search(SearchQuery(text: text)))?.map(\.name) ?? [] }
        let coordinator = run(store) { names("zanzibar") == ["a.txt"] }

        let followed = expectation(description: "new document read")
        followed.assertForOverFulfill = false
        coordinator.onChange = { _ in
            if names("madagascar") == ["b.md"] {
                followed.fulfill()
            }
        }
        try Data("Trip to Madagascar".utf8).write(to: temp.url.appendingPathComponent("data/b.md"))
        wait(for: [followed], timeout: 15)
        coordinator.stop()
    }

    func testAnUnpluggedRootIsKeptThenRefreshedWhenBack() throws {
        let disk = try temp.directory("disk")
        try temp.file("disk/a.txt", size: 10)
        let store = try IndexStore.open(at: databaseURL)
        _ = try store.addRoot(path: disk.path, exclusions: [])
        run(store) { Self.total(store, disk.path) == 10 }.stop()

        let away = temp.url.appendingPathComponent("away")
        try FileManager.default.moveItem(at: disk, to: away)
        let isOffline = { @Sendable in (try? store.roots().first?.isOffline) == true }
        let coordinator = run(store) { isOffline() }
        XCTAssertEqual(Self.total(store, disk.path), 10, "kept as a catalog, not rescanned away")

        try temp.file("away/b.txt", size: 5)
        try FileManager.default.moveItem(at: away, to: disk)
        waitForChange(coordinator, after: { coordinator.volumesChanged() }, until: {
            Self.total(store, disk.path) == 15 && !isOffline()
        })
        coordinator.stop()
    }

    func testRelaunchCatchesUpWithChangesMadeWhileClosed() throws {
        let path = dataPath
        do {
            let store = try IndexStore.open(at: databaseURL)
            _ = try store.addRoot(path: temp.url.path, exclusions: [])
            run(store) { Self.total(store, path) == 10 }.stop()
        }

        // "App closed": change the disk.
        try temp.file("data/while-closed.txt", size: 90)

        let reopened = try IndexStore.open(at: databaseURL)
        let scannedAt = try XCTUnwrap(reopened.roots().first?.scannedAt)
        let relaunched = run(reopened) { Self.total(reopened, path) == 100 }
        XCTAssertEqual(try reopened.roots().first?.scannedAt, scannedAt, "caught up without a full rescan")
        relaunched.stop()
    }

    func testSeveralRootsAreScannedCorrectly() throws {
        try temp.file("other/b.bin", size: 40)
        let store = try IndexStore.open(at: databaseURL)
        let path = dataPath
        let other = temp.url.appendingPathComponent("other").path
        _ = try store.addRoot(path: path, exclusions: [])
        _ = try store.addRoot(path: other, exclusions: [])
        run(store) { Self.total(store, path) == 10 && Self.total(store, other) == 40 }.stop()
        XCTAssertTrue(try store.roots().allSatisfy { $0.scannedAt != nil })
    }

    /// Runs `action`, then waits until `condition` holds after a change notification. The
    /// listener is in place before the action starts, so no notification is missed.
    private func waitForChange(
        _ coordinator: IndexCoordinator, after action: () -> Void, until condition: @escaping @Sendable () -> Bool
    ) {
        let done = expectation(description: "condition met")
        done.assertForOverFulfill = false
        coordinator.onChange = { _ in
            if condition() {
                done.fulfill()
            }
        }
        action()
        wait(for: [done], timeout: 15)
    }

    func testRootsCanBeAddedRemovedAndReExcludedWhileRunning() throws {
        try temp.file("data/sub/b.bin", size: 30)
        let store = try IndexStore.open(at: databaseURL)
        let path = dataPath
        let coordinator = IndexCoordinator(store: store)
        coordinator.start()

        waitForChange(
            coordinator, after: { coordinator.addRoot(path: path, exclusions: []) },
            until: { Self.total(store, path) == 40 }
        )
        let root = try XCTUnwrap(store.roots().first)
        XCTAssertEqual(try store.summary(of: root).items, 3, "a.txt, sub, sub/b.bin")

        waitForChange(
            coordinator, after: { coordinator.setExclusions(root.id, [path + "/sub"]) },
            until: { Self.total(store, path) == 10 }
        )
        XCTAssertNil(try store.itemID(forPath: path + "/sub"))

        waitForChange(
            coordinator, after: { coordinator.removeRoot(root.id) },
            until: { (try? store.roots().isEmpty) == true }
        )
        XCTAssertEqual(try store.itemCount(), 0)
        coordinator.stop()
    }

    func testANewRootOrAnotherEventHistoryNeedsAScan() throws {
        let store = try IndexStore.inMemory()
        let root = try store.addRoot(path: temp.url.path, exclusions: [])
        XCTAssertTrue(IndexCoordinator.needsScan(root))
        try store.markScanned(root.id, eventID: 1, volumeUUID: FolderWatcher.volumeUUID(for: temp.url.path))
        XCTAssertFalse(try IndexCoordinator.needsScan(XCTUnwrap(store.roots().first)))
        try store.markScanned(root.id, eventID: 1, volumeUUID: "another history")
        XCTAssertTrue(try IndexCoordinator.needsScan(XCTUnwrap(store.roots().first)))
    }
}
