@testable import Arbor
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
}
