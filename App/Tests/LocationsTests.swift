@testable import Arbor
import DiskKit
import XCTest

final class LocationsTests: XCTestCase {
    private var home: URL!

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("LocationsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
    }

    private func make(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: home.appendingPathComponent(path),
            withIntermediateDirectories: true
        )
    }

    func testNoCloudFoldersMeansNoCloudPlaces() {
        XCTAssertEqual(Locations.cloud(home: home), [])
    }

    func testFindsICloudDriveAndOneDriveOnly() throws {
        try make("Library/Mobile Documents/com~apple~CloudDocs")
        try make("Library/CloudStorage/OneDrive-Personal")
        try make("Library/CloudStorage/OneDrive-Contoso")
        try make("Library/CloudStorage/Dropbox")
        let places = Locations.cloud(home: home)
        XCTAssertEqual(places.map(\.kind), [.iCloudDrive, .oneDrive, .oneDrive])
        XCTAssertEqual(places.dropFirst().map(\.url.lastPathComponent), ["OneDrive-Contoso", "OneDrive-Personal"])
    }

    func testAllStartsWithThisComputer() throws {
        let first = try XCTUnwrap(Locations.all(home: home).first)
        XCTAssertEqual(first.kind, .computer)
        XCTAssertEqual(first.url.path, "/")
        XCTAssertFalse(Locations.all(home: home).contains { $0.kind == .volume && $0.url.path == "/" })
    }

    func testSharedListsMountedSharesThenDisconnectedOnesThenServers() throws {
        let media = try XCTUnwrap(URL(string: "smb://nas.local/Media"))
        let backup = try XCTUnwrap(URL(string: "smb://nas.local/Backup"))
        let mounted = Volume(url: URL(fileURLWithPath: "/Volumes/Media"), name: "Media", remountURL: media)
        let places = Locations.shared(
            mounted: [mounted],
            remembered: [RememberedShare(url: backup, name: "Backup"), RememberedShare(url: media, name: "Media")],
            servers: [NetworkServer(name: "NAS")]
        )
        XCTAssertEqual(places.map(\Place.kind), [Place.Kind.share, .disconnectedShare, .server])
        XCTAssertEqual(places.map(\Place.url), [mounted.url, backup, NetworkServer(name: "NAS").url])
        XCTAssertEqual(places.map(\Place.isRemote), [false, true, true])
    }

    @MainActor
    func testRememberedShareShowsInTheSharedSectionAndCanBeForgotten() throws {
        let database = try AppDatabase.inMemory()
        let url = try XCTUnwrap(URL(string: "smb://nas-\(UUID().uuidString).local/Photos"))
        try database.rememberShare(url, name: "Photos")
        let sidebar = SidebarViewController(database: database)
        sidebar.loadView()
        let node = try XCTUnwrap(sidebar.section(.shared)?.children.first { node in
            if case let .place(place) = node.kind {
                return place.url == url
            }
            return false
        })
        let row = sidebar.outlineView.row(forItem: node)
        let cell = try XCTUnwrap(sidebar.outlineView.view(
            atColumn: 0,
            row: row,
            makeIfNecessary: true
        ) as? NSTableCellView)
        XCTAssertEqual(cell.textField?.stringValue, "Photos")
        XCTAssertEqual(cell.textField?.textColor, .secondaryLabelColor)
        try database.forgetShare(url)
        sidebar.reload()
        XCTAssertFalse(sidebar.section(.shared)?.children.contains { $0 === node } ?? false)
    }
}
