@testable import IndexKit
import XCTest

/// Root/{Annual report.pdf (300), Report-2025.txt (20), prepare.txt (5), Résumé.docx (40),
///       photos/{beach.jpg (5000)}, Reports/ (folder)}
final class IndexSearchTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var store: IndexStore!
    private var root: IndexRoot!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        try temp.file("Annual report.pdf", size: 300)
        try temp.file("Report-2025.txt", size: 20, modified: Date(timeIntervalSince1970: 1_000_000))
        try temp.file("prepare.txt", size: 5)
        try temp.file("Résumé.docx", size: 40)
        try temp.file("photos/beach.jpg", size: 5000)
        try temp.directory("Reports")
        store = try IndexStore.inMemory()
        root = try store.addRoot(path: temp.url.path, exclusions: [])
        try IndexScanner(store: store).scan(root)
    }

    override func tearDown() {
        temp.remove()
    }

    private func names(_ query: SearchQuery) throws -> [String] {
        try store.search(query).map(\.name).sorted()
    }

    func testWordPrefixesMatch() throws {
        XCTAssertEqual(try names(SearchQuery(text: "rep")), ["Annual report.pdf", "Report-2025.txt", "Reports"])
    }

    func testEveryWordMustMatch() throws {
        XCTAssertEqual(try names(SearchQuery(text: "annual rep")), ["Annual report.pdf"])
    }

    func testAccentsAndCaseAreIgnored() throws {
        XCTAssertEqual(try names(SearchQuery(text: "RESUME")), ["Résumé.docx"])
    }

    func testResultsCarryPathAndSizes() throws {
        let result = try XCTUnwrap(store.search(SearchQuery(text: "beach")).first)
        XCTAssertEqual(result.path, temp.url.appendingPathComponent("photos/beach.jpg").path)
        XCTAssertEqual(result.totalSize, 5000)
        XCTAssertFalse(result.isDirectory)
    }

    func testKindAndCategoryFilters() throws {
        XCTAssertEqual(try names(SearchQuery(text: "rep", kind: .folders)), ["Reports"])
        XCTAssertEqual(
            try names(SearchQuery(text: "rep", category: .documents)),
            ["Annual report.pdf", "Report-2025.txt"]
        )
        XCTAssertEqual(try names(SearchQuery(category: .images)), ["beach.jpg"], "a filter alone is a search")
    }

    func testSizeAndDateFilters() throws {
        XCTAssertEqual(try names(SearchQuery(text: "rep", kind: .files, minSize: 100)), ["Annual report.pdf"])
        XCTAssertEqual(try names(SearchQuery(text: "rep", kind: .files, maxSize: 100)), ["Report-2025.txt"])
        XCTAssertEqual(
            try names(SearchQuery(text: "rep", kind: .files, modifiedBefore: Date(timeIntervalSince1970: 2_000_000))),
            ["Report-2025.txt"]
        )
        XCTAssertEqual(
            try names(SearchQuery(text: "rep", kind: .files, modifiedAfter: Date(timeIntervalSince1970: 2_000_000))),
            ["Annual report.pdf"]
        )
    }

    func testRootFilter() throws {
        XCTAssertEqual(try names(SearchQuery(text: "beach", rootID: root.id)), ["beach.jpg"])
        XCTAssertEqual(try names(SearchQuery(text: "beach", rootID: root.id + 1)), [])
    }

    func testEmptyQueryFindsNothing() throws {
        XCTAssertEqual(try names(SearchQuery()), [])
    }

    func testIndexFollowsUpdates() throws {
        try temp.file("photos/reporter.jpg", size: 1)
        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("prepare.txt"))
        try IndexUpdater(store: store).apply([
            FolderChange(path: temp.url.appendingPathComponent("photos").path, mustRescanSubfolders: false),
            FolderChange(path: temp.url.path, mustRescanSubfolders: false),
        ])
        XCTAssertTrue(try names(SearchQuery(text: "reporter")).contains("reporter.jpg"))
        XCTAssertEqual(try names(SearchQuery(text: "prepare")), [])
    }

    func testQuerySyntaxIsEscaped() throws {
        for text in ["\"", "rep*", "OR", "a\" OR \"b", "-x", "NEAR(", "(", "*"] {
            XCTAssertNoThrow(try store.search(SearchQuery(text: text)), text)
        }
    }

    func testResultsAreLimited() throws {
        XCTAssertEqual(try store.search(SearchQuery(text: "rep", limit: 2)).count, 2)
    }
}
