import DiskKit
import XCTest

final class DiskKitTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(DiskKit.name, "DiskKit")
    }
}
