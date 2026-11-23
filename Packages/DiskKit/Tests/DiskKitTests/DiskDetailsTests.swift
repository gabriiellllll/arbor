import DiskArbitration
@testable import DiskKit
import XCTest

final class DiskDetailsTests: XCTestCase {
    func testStartupVolumeDetails() throws {
        let details = try XCTUnwrap(DiskDetails.of(volume: URL(fileURLWithPath: "/")))
        XCTAssertFalse(details.name.isEmpty)
        XCTAssertNotNil(details.volumeUUID)
        XCTAssertGreaterThan(details.capacity ?? 0, 0)
        XCTAssertNotNil(details.fileSystem)
        // Device strings depend on the hardware (virtual machines have none): they must match
        // what Disk Arbitration says, trimmed, with empty strings as nil.
        let session = try XCTUnwrap(DASessionCreate(nil))
        let disk = try XCTUnwrap(DADiskCreateFromVolumePath(nil, session, URL(fileURLWithPath: "/") as CFURL))
        let description = try XCTUnwrap(DADiskCopyDescription(disk) as? [String: Any])
        let expected = { (key: CFString) -> String? in
            let value = (description[key as String] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value : nil
        }
        XCTAssertEqual(details.vendor, expected(kDADiskDescriptionDeviceVendorKey))
        XCTAssertEqual(details.model, expected(kDADiskDescriptionDeviceModelKey))
        XCTAssertEqual(details.connection, expected(kDADiskDescriptionDeviceProtocolKey))
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
