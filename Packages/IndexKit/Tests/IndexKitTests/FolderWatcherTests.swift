@testable import IndexKit
import XCTest

final class FolderWatcherTests: XCTestCase {
    private var temp: TemporaryDirectory!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
    }

    override func tearDown() {
        temp.remove()
    }

    private func expectChange(at path: String, after change: () throws -> Void) throws {
        let reported = expectation(description: "change at \(path)")
        reported.assertForOverFulfill = false
        let watcher = FolderWatcher(latency: 0.05) { changes in
            if changes.contains(where: { $0.path == path }) {
                reported.fulfill()
            }
        }
        watcher.watch([temp.url.path])
        // FSEvents only reports changes made after the stream starts.
        Thread.sleep(forTimeInterval: 0.5)
        try change()
        wait(for: [reported], timeout: 10)
    }

    func testReportsNewFileInWatchedFolder() throws {
        try expectChange(at: temp.url.path) {
            try temp.file("new.txt")
        }
    }

    func testReportsChangesInSubfolders() throws {
        let sub = try temp.directory("sub")
        try expectChange(at: sub.path) {
            try temp.file("sub/inner.txt")
        }
    }

    func testStopsReportingAfterUnwatch() throws {
        let unexpected = expectation(description: "no change reported")
        unexpected.isInverted = true
        let watcher = FolderWatcher(latency: 0.05) { _ in unexpected.fulfill() }
        watcher.watch([temp.url.path])
        watcher.watch([])
        Thread.sleep(forTimeInterval: 0.5)
        try temp.file("ignored.txt")
        wait(for: [unexpected], timeout: 2)
    }

    func testChangesMadeWhileNotWatchingAreCaughtUp() throws {
        let since = FolderWatcher.currentEventID
        let folder = temp.url.path
        try temp.file("made-while-closed.txt")
        let caughtUp = expectation(description: "replayed change")
        caughtUp.assertForOverFulfill = false
        let watcher = FolderWatcher(latency: 0.05) { changes in
            if changes.contains(where: { $0.path == folder && $0.eventID > since }) {
                caughtUp.fulfill()
            }
        }
        watcher.watch([temp.url.path], since: since)
        wait(for: [caughtUp], timeout: 10)
    }

    func testVolumeUUIDIdentifiesTheEventHistory() {
        let uuid = FolderWatcher.volumeUUID(for: temp.url.path)
        XCTAssertNotNil(uuid)
        XCTAssertEqual(uuid, FolderWatcher.volumeUUID(for: NSTemporaryDirectory()))
        XCTAssertNil(FolderWatcher.volumeUUID(for: "/nonexistent/\(UUID().uuidString)"))
    }

    func testCanonicalPathResolvesPrivatePrefix() {
        XCTAssertEqual(FolderWatcher.canonicalPath(of: URL(fileURLWithPath: "/tmp")), "/private/tmp")
    }

    func testNormalizesTrailingSlash() {
        XCTAssertEqual(FolderWatcher.normalized("/a/b/"), "/a/b")
        XCTAssertEqual(FolderWatcher.normalized("/"), "/")
    }
}
