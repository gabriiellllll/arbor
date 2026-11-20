@testable import FileOpsKit
import XCTest

final class UniqueNameTests: XCTestCase {
    func testFreeNameIsKept() {
        XCTAssertEqual(UniqueName.make(for: "report.pdf", avoiding: []), "report.pdf")
    }

    func testTakenNameGetsNumberTwoBeforeTheExtension() {
        XCTAssertEqual(UniqueName.make(for: "report.pdf", avoiding: ["report.pdf"]), "report 2.pdf")
    }

    func testCountsUpPastTakenNumbers() {
        XCTAssertEqual(
            UniqueName.make(for: "report.pdf", avoiding: ["report.pdf", "report 2.pdf", "report 3.pdf"]),
            "report 4.pdf"
        )
    }

    func testANumberedNameContinuesFromItsNumber() {
        XCTAssertEqual(UniqueName.make(for: "report 2.pdf", avoiding: ["report 2.pdf"]), "report 3.pdf")
    }

    func testFoldersAndNamesWithoutExtension() {
        XCTAssertEqual(UniqueName.make(for: "Photos", avoiding: ["Photos"]), "Photos 2")
    }

    func testOnlyTheLastExtensionIsKeptAside() {
        XCTAssertEqual(UniqueName.make(for: "archive.tar.gz", avoiding: ["archive.tar.gz"]), "archive.tar 2.gz")
    }

    func testDotFilesAreNamesNotExtensions() {
        XCTAssertEqual(UniqueName.make(for: ".env", avoiding: [".env"]), ".env 2")
    }

    func testComparisonIgnoresCaseLikeTheFileSystem() {
        XCTAssertEqual(UniqueName.make(for: "Report.pdf", avoiding: ["report.pdf"]), "Report 2.pdf")
    }
}
