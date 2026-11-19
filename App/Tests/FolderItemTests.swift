@testable import Arbor
import IndexKit
import XCTest

final class FolderItemTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/tmp/root", isDirectory: true)

    private func item(_ name: String, kind: DirectoryEntry.Kind = .file, size: Int64 = 0,
                      modified: TimeInterval = 0) -> FolderItem
    {
        FolderItem(entry: DirectoryEntry(
            name: name, kind: kind, size: size, allocatedSize: size, itemCount: nil,
            created: Date(timeIntervalSince1970: 0), modified: Date(timeIntervalSince1970: modified),
            fileID: 1, isHidden: false
        ), in: folder)
    }

    func testDirectoriesAreFoldersButPackagesAreNot() {
        XCTAssertTrue(item("Projects", kind: .directory).isFolder)
        XCTAssertTrue(item("v1.2", kind: .directory).isFolder)
        XCTAssertFalse(item("Safari.app", kind: .directory).isFolder)
        XCTAssertFalse(item("notes.txt").isFolder)
    }

    func testURLIsInsideFolder() {
        XCTAssertEqual(item("Projects", kind: .directory).url.path, "/tmp/root/Projects")
    }

    func testSortByNameUsesFinderOrder() {
        let names = [item("file10"), item("File2"), item("file1")].sorted(by: .name, ascending: true).map(\.name)
        XCTAssertEqual(names, ["file1", "File2", "file10"])
    }

    func testSortBySizeBreaksTiesByName() {
        let items = [item("b", size: 5), item("a", size: 5), item("c", size: 1)]
        XCTAssertEqual(items.sorted(by: .size, ascending: true).map(\.name), ["c", "a", "b"])
        XCTAssertEqual(items.sorted(by: .size, ascending: false).map(\.name), ["b", "a", "c"])
    }

    func testSortByModified() {
        let items = [item("old", modified: 1), item("new", modified: 9)]
        XCTAssertEqual(items.sorted(by: .modified, ascending: false).map(\.name), ["new", "old"])
    }
}
