@testable import DiskKit
import XCTest

final class ServerBrowserTests: XCTestCase {
    func testServerURLUsesItsEscapedBonjourName() {
        XCTAssertEqual(
            NetworkServer(name: "Ann’s Mac mini").url.absoluteString,
            "smb://Ann%E2%80%99s%20Mac%20mini._smb._tcp.local"
        )
    }

    func testServersAreUniqueAndSorted() {
        XCTAssertEqual(
            ServerBrowser.servers(named: ["NAS 10", "nas 2", "NAS 10", "Atlas"]).map(\.name),
            ["Atlas", "nas 2", "NAS 10"]
        )
    }
}
