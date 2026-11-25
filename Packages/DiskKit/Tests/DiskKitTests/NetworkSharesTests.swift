@testable import DiskKit
import XCTest

final class NetworkSharesTests: XCTestCase {
    func testUnsupportedSchemeFailsWithoutUI() async throws {
        do {
            _ = try await NetworkShares.mount(XCTUnwrap(URL(string: "arbor-test://nowhere/share")), allowUI: false)
            XCTFail("mounted an unsupported URL")
        } catch {
            XCTAssertFalse(NetworkShares.isCancellation(error))
        }
    }

    func testCancellationCodes() {
        XCTAssertTrue(NetworkShares.isCancellation(NetworkShares.error(ECANCELED)))
        XCTAssertTrue(NetworkShares.isCancellation(NetworkShares.error(Int32(userCanceledErr))))
        XCTAssertFalse(NetworkShares.isCancellation(NetworkShares.error(-5998)))
    }

    func testAddressesDefaultToSMB() {
        XCTAssertEqual(NetworkShares.url(from: " nas.local/Media ")?.absoluteString, "smb://nas.local/Media")
        XCTAssertEqual(NetworkShares.url(from: "afp://old-mac.local")?.absoluteString, "afp://old-mac.local")
        XCTAssertEqual(NetworkShares.url(from: "nfs://10.0.0.2/export")?.absoluteString, "nfs://10.0.0.2/export")
        XCTAssertNil(NetworkShares.url(from: ""))
        XCTAssertNil(NetworkShares.url(from: "smb://"))
        XCTAssertNil(NetworkShares.url(from: "bad host/share"))
    }
}
