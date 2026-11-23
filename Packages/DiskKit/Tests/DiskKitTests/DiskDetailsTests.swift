@testable import DiskKit
import XCTest

final class DiskDetailsTests: XCTestCase {
    func testStartupVolumeDetails() throws {
        let details = try XCTUnwrap(DiskDetails.of(volume: URL(fileURLWithPath: "/")))
        XCTAssertFalse(details.name.isEmpty)
        XCTAssertNotNil(details.volumeUUID)
        XCTAssertGreaterThan(details.capacity ?? 0, 0)
        XCTAssertNotNil(details.fileSystem)
        XCTAssertNotNil(details.model, "Disk Arbitration describes the device")
        XCTAssertNotEqual(details.vendor, "", "empty strings become nil")
    }

    func testNothingMountedThere() {
        XCTAssertNil(DiskDetails.of(volume: URL(fileURLWithPath: "/no/such/volume-\(UUID().uuidString)")))
    }

    func testDetailsRoundTripAsJSON() throws {
        let details = DiskDetails(
            name: "Backup", volumeUUID: "ABC", vendor: "Samsung", model: "T7", serialNumber: "S1",
            connection: "USB", capacity: 1_000_000, fileSystem: "APFS"
        )
        XCTAssertEqual(try JSONDecoder().decode(DiskDetails.self, from: JSONEncoder().encode(details)), details)
    }
}
