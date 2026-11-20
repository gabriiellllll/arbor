@testable import FileOpsKit
import XCTest

final class FinderTagsTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinderTagsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: folder)
    }

    private func file(_ name: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data().write(to: url)
        return url
    }

    func testNewFileHasNoTags() throws {
        XCTAssertEqual(try FinderTags.tags(of: file("a")), [])
    }

    func testSetTagsRoundTrips() throws {
        let url = try file("a")
        try FinderTags.setTags(["Red", "Project X"], on: url)
        XCTAssertEqual(try FinderTags.tags(of: url), ["Red", "Project X"])
        try FinderTags.setTags([], on: url)
        XCTAssertEqual(try FinderTags.tags(of: url), [])
    }

    func testToggleAddsToAllUnlessAllHaveIt() throws {
        let first = try file("a")
        let second = try file("b")
        try FinderTags.setTags(["Blue"], on: first)

        try FinderTags.toggle("Blue", on: [first, second])
        XCTAssertEqual(try FinderTags.tags(of: second), ["Blue"], "added where missing")
        XCTAssertEqual(try FinderTags.tags(of: first), ["Blue"], "not duplicated")

        try FinderTags.toggle("Blue", on: [first, second])
        XCTAssertEqual(try FinderTags.tags(of: first), [])
        XCTAssertEqual(try FinderTags.tags(of: second), [])
    }

    func testToggleKeepsOtherTags() throws {
        let url = try file("a")
        try FinderTags.setTags(["Green", "Work"], on: url)
        try FinderTags.toggle("Green", on: [url])
        XCTAssertEqual(try FinderTags.tags(of: url), ["Work"])
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try FinderTags.setTags(["Red"], on: folder.appendingPathComponent("missing")))
    }
}
