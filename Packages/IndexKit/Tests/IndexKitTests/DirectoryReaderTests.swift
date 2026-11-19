@testable import IndexKit
import XCTest

final class DirectoryReaderTests: XCTestCase {
    private var temp: TemporaryDirectory!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
    }

    override func tearDown() {
        temp.remove()
    }

    private func entry(_ name: String, in entries: [DirectoryEntry]) throws -> DirectoryEntry {
        try XCTUnwrap(entries.first { $0.name == name }, "missing \(name)")
    }

    func testEmptyDirectoryHasNoEntries() throws {
        XCTAssertEqual(try DirectoryReader.entries(at: temp.url), [])
    }

    func testReadsFilesWithSizeAndDates() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let url = try temp.file("report.pdf", size: 1234, modified: date)
        let file = try entry("report.pdf", in: DirectoryReader.entries(at: temp.url))
        XCTAssertEqual(file.kind, .file)
        XCTAssertEqual(file.size, 1234)
        XCTAssertGreaterThanOrEqual(file.allocatedSize, 1234)
        XCTAssertEqual(file.modified, date)
        XCTAssertNil(file.itemCount)
        let inode = try FileManager.default.attributesOfItem(atPath: url.path)[.systemFileNumber] as? UInt64
        XCTAssertEqual(file.fileID, inode)
    }

    func testReadsDirectoriesWithItemCount() throws {
        try temp.file("folder/a")
        try temp.file("folder/b")
        try temp.directory("folder/sub")
        let folder = try entry("folder", in: DirectoryReader.entries(at: temp.url))
        XCTAssertEqual(folder.kind, .directory)
        XCTAssertEqual(folder.itemCount, 3)
        XCTAssertEqual(folder.size, 0)
    }

    func testReadsSymlinksWithoutFollowingThem() throws {
        let target = try temp.directory("target")
        try FileManager.default.createSymbolicLink(
            at: temp.url.appendingPathComponent("link"), withDestinationURL: target
        )
        XCTAssertEqual(try entry("link", in: DirectoryReader.entries(at: temp.url)).kind, .symlink)
    }

    func testDotFilesAndHiddenFlagAreHidden() throws {
        try temp.file(".secret")
        var hidden = try temp.file("flagged")
        var values = URLResourceValues()
        values.isHidden = true
        try hidden.setResourceValues(values)
        try temp.file("visible")
        let entries = try DirectoryReader.entries(at: temp.url)
        XCTAssertTrue(try entry(".secret", in: entries).isHidden)
        XCTAssertTrue(try entry("flagged", in: entries).isHidden)
        XCTAssertFalse(try entry("visible", in: entries).isHidden)
    }

    func testUnicodeNamesRoundTrip() throws {
        let names = ["Café", "日本語.txt", "emoji 🌳", "spaces and (parens)"]
        for name in names {
            try temp.file(name)
        }
        let read = try DirectoryReader.entries(at: temp.url).map(\.name)
        for name in names {
            XCTAssertTrue(read
                .contains { $0.precomposedStringWithCanonicalMapping == name.precomposedStringWithCanonicalMapping })
        }
    }

    func testManyEntriesSpanSeveralBuffers() throws {
        for index in 0 ..< 3000 {
            try temp.file("file-\(index)-with-a-rather-long-name-to-fill-the-buffer-faster.txt")
        }
        XCTAssertEqual(try DirectoryReader.entries(at: temp.url).count, 3000)
    }

    func testMissingDirectoryThrows() {
        XCTAssertThrowsError(try DirectoryReader.entries(at: temp.url.appendingPathComponent("nope"))) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOENT)
        }
    }

    func testFileInsteadOfDirectoryThrows() throws {
        let file = try temp.file("plain")
        XCTAssertThrowsError(try DirectoryReader.entries(at: file)) { error in
            XCTAssertEqual((error as? POSIXError)?.code, .ENOTDIR)
        }
    }
}
