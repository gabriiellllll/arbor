import FileOpsKit
import Foundation

/// UI tests launch the app with `ARBOR_UI_TEST_FIXTURE=1`: the app then builds a small
/// folder tree in a fresh temporary directory and opens it, so tests never touch user files:
/// Root/{Alpha/{Inner, OnlyA, data.bin (2000 bytes)}, Beta/{Inner}, notes.txt (tagged Red)}.
/// Next to it, Archive/Photos/beach.jpg is indexed as a disk, then deleted: an unplugged disk
/// in the catalog.
enum UITestFixture {
    static let environmentKey = "ARBOR_UI_TEST_FIXTURE"

    static var isActive: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    static func makeIfRequested() throws -> URL? {
        guard isActive else { return nil }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArborUITests-\(UUID().uuidString)/Root", isDirectory: true)
        for folder in ["Alpha/Inner", "Alpha/OnlyA", "Beta/Inner"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(folder), withIntermediateDirectories: true
            )
        }
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.txt"))
        try FinderTags.setTags(["Red"], on: root.appendingPathComponent("notes.txt"))
        try Data(count: 2000).write(to: root.appendingPathComponent("Alpha/data.bin"))
        let photos = unpluggedDisk(of: root).appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        try Data(count: 100).write(to: photos.appendingPathComponent("beach.jpg"))
        return root
    }

    static func unpluggedDisk(of fixture: URL) -> URL {
        fixture.deletingLastPathComponent().appendingPathComponent("Archive", isDirectory: true)
    }

    /// UI tests trash into a folder next to the fixture, never the user's Trash.
    static func trash(in fixture: URL) -> FileOperationRunner.Trash {
        let folder = fixture.deletingLastPathComponent().appendingPathComponent("Trash", isDirectory: true)
        return { url in
            let slot = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
            let destination = slot.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }
}
