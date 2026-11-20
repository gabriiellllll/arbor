@testable import IndexKit
import XCTest

/// Finder tags in the index. Root/{red.txt [Red], both.txt [Red, Work], plain.txt, docs/{deep.txt [Work]}}
final class IndexTagsTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var store: IndexStore!
    private var root: IndexRoot!

    private func tag(_ path: String, _ tags: [String]) throws {
        let url = temp.url.appendingPathComponent(path)
        try (url as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
    }

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        try temp.file("red.txt")
        try temp.file("both.txt")
        try temp.file("plain.txt")
        try temp.file("docs/deep.txt")
        try tag("red.txt", ["Red"])
        try tag("both.txt", ["Red", "Work"])
        try tag("docs/deep.txt", ["Work"])
        store = try IndexStore.inMemory()
        root = try store.addRoot(path: temp.url.path, exclusions: [])
        try IndexScanner(store: store).scan(root)
        try IndexScanner(store: store).readTags(root)
    }

    override func tearDown() {
        temp.remove()
    }

    private func tagged(_ name: String) throws -> [String] {
        try store.search(SearchQuery(tag: name)).map(\.name).sorted()
    }

    func testReaderReturnsTagNamesWithoutColors() {
        XCTAssertEqual(TagReader.tags(atPath: temp.url.appendingPathComponent("both.txt").path), ["Red", "Work"])
        XCTAssertEqual(TagReader.tags(atPath: temp.url.appendingPathComponent("plain.txt").path), [])
        XCTAssertEqual(TagReader.tags(atPath: "/nonexistent/\(UUID().uuidString)"), [])
    }

    func testTagsAreSearchable() throws {
        XCTAssertEqual(try tagged("Red"), ["both.txt", "red.txt"])
        XCTAssertEqual(try tagged("Work"), ["both.txt", "deep.txt"])
        XCTAssertEqual(try store.search(SearchQuery(text: "both", tag: "Work")).map(\.name), ["both.txt"])
    }

    func testTagCountsListEveryTag() throws {
        XCTAssertEqual(try store.tagCounts(), [TagCount(name: "Red", count: 2), TagCount(name: "Work", count: 2)])
    }

    func testTagReadAtIsRecorded() throws {
        XCTAssertNotNil(try store.roots().first?.tagsReadAt)
    }

    func testChangedTagsAreReadOnRefresh() throws {
        // Adding a tag changes an extended attribute only: the file's date stays the same.
        try tag("plain.txt", ["Red"])
        try tag("red.txt", [])
        try IndexUpdater(store: store).apply([FolderChange(path: temp.url.path, mustRescanSubfolders: false)])
        XCTAssertEqual(try tagged("Red"), ["both.txt", "plain.txt"])
    }

    func testNewSubfoldersHaveTheirTagsRead() throws {
        try temp.file("new/fresh.txt")
        try tag("new/fresh.txt", ["Blue"])
        try IndexUpdater(store: store).apply([FolderChange(path: temp.url.path, mustRescanSubfolders: false)])
        XCTAssertEqual(try tagged("Blue"), ["fresh.txt"])
    }

    func testDeletingItemsDropsTheirTags() throws {
        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("docs"))
        try IndexUpdater(store: store).apply([FolderChange(path: temp.url.path, mustRescanSubfolders: false)])
        XCTAssertEqual(try tagged("Work"), ["both.txt"])
    }
}
