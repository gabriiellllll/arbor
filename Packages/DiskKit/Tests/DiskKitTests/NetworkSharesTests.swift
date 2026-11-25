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
}
