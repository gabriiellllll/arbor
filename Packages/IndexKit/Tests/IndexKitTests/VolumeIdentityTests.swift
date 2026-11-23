@testable import IndexKit
import XCTest

final class VolumeIdentityTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var store: IndexStore!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        store = try IndexStore.inMemory()
    }

    override func tearDown() {
        temp.remove()
    }

    private func root(_ id: Int64) throws -> IndexRoot {
        try XCTUnwrap(store.roots().first { $0.id == id })
    }

    func testAvailabilityNeedsTheFolderAndTheSameDisk() throws {
        let folder = try temp.directory("Disk")
        let root = try store.addRoot(path: folder.path, exclusions: [])
        XCTAssertTrue(root.isAvailable)

        let real = try XCTUnwrap(folder.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString)
        try store.setVolume(root.id, path: folder.path, volumeID: "another disk")
        XCTAssertFalse(try self.root(root.id).isAvailable, "another disk under the same name")
        try store.setVolume(root.id, path: folder.path, volumeID: real)
        XCTAssertTrue(try self.root(root.id).isAvailable)

        try FileManager.default.moveItem(at: folder, to: temp.url.appendingPathComponent("Unplugged"))
        XCTAssertFalse(try self.root(root.id).isAvailable)
    }

    func testTheStartupVolumeIsListed() {
        XCTAssertTrue(MountedVolume.current().contains { $0.path == "/" })
    }

    func testVolumeRootsGetTheirUUIDAndFollowTheirDisk() throws {
        let mounted = try temp.directory("Backup 1")
        let gone = temp.url.appendingPathComponent("Backup").path
        let volume = try store.addRoot(path: mounted.path, exclusions: [])
        let moved = try store.addRoot(path: gone, exclusions: [])
        try store.setVolume(moved.id, path: gone, volumeID: "U2")
        let folder = try store.addRoot(path: temp.directory("Folder").path, exclusions: [])

        let changed = try store.updateVolumes([
            MountedVolume(path: mounted.path, uuid: "U1"), MountedVolume(path: temp.url.path, uuid: "U2"),
        ])
        XCTAssertEqual(Set(changed), [volume.id, moved.id])
        XCTAssertEqual(try root(volume.id).volumeID, "U1", "a mount point gets its UUID")
        XCTAssertEqual(try root(moved.id).path, temp.url.path, "an unplugged disk follows its UUID")
        XCTAssertNil(try root(folder.id).volumeID, "plain folders have no volume ID")
    }

    func testCatalogListsAFolderOfAnUnpluggedDisk() throws {
        try temp.file("Disk/docs/a.txt", size: 12)
        try temp.directory("Disk/docs/sub")
        let disk = temp.url.appendingPathComponent("Disk")
        let root = try store.addRoot(path: disk.path, exclusions: [])
        try IndexScanner(store: store).scan(root)
        try FileManager.default.removeItem(at: disk)

        let entries = try XCTUnwrap(store.catalogEntries(ofFolder: disk.appendingPathComponent("docs").path))
        XCTAssertEqual(entries.map(\.name).sorted(), ["a.txt", "sub"])
        XCTAssertEqual(entries.first { $0.name == "a.txt" }?.size, 12)
        XCTAssertEqual(entries.first { $0.name == "sub" }?.kind, .directory)
        XCTAssertNil(try store.catalogEntries(ofFolder: disk.appendingPathComponent("nope").path))
    }

    func testOfflineFlagAndDetailsAreSaved() throws {
        let root = try store.addRoot(path: temp.url.path, exclusions: [])
        try store.setOffline(root.id, true)
        try store.setDetails(root.id, Data("{}".utf8))
        XCTAssertTrue(try self.root(root.id).isOffline)
        XCTAssertEqual(try self.root(root.id).details, Data("{}".utf8))
    }
}
