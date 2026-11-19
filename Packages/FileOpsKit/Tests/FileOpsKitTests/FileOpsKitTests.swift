import FileOpsKit
import XCTest

final class FileOpsKitTests: XCTestCase {
    func testModuleName() {
        XCTAssertEqual(FileOpsKit.name, "FileOpsKit")
    }
}
