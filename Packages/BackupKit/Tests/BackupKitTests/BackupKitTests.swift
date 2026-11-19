import BackupKit
import XCTest

final class BackupKitTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(BackupKit.name, "BackupKit")
    }
}
