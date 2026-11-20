@testable import Arbor
import IndexKit
import XCTest

/// Settings › Index on a temporary folder (never the startup volume).
@MainActor
final class IndexSettingsTests: XCTestCase {
    private var folder: URL!
    private var service: IndexService!
    private var model: IndexSettingsModel!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexSettingsTests-\(UUID().uuidString)/Root", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Keep"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Skip"),
            withIntermediateDirectories: true
        )
        try Data(count: 100).write(to: folder.appendingPathComponent("Keep/a.bin"))
        try Data(count: 900).write(to: folder.appendingPathComponent("Skip/b.bin"))
        service = try IndexService.openForUITests(fixture: folder)
        service.start()
        model = IndexSettingsModel(index: service)
    }

    override func tearDown() async throws {
        service.stop()
        try? FileManager.default.removeItem(at: folder.deletingLastPathComponent())
    }

    private func waitUntil(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition(), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            model.refresh()
        }
        XCTAssertTrue(condition(), message)
    }

    func testShowsTheRootWithItsSummary() async throws {
        try await waitUntil("scanned") { model.roots.first?.root.scannedAt != nil }
        let row = try XCTUnwrap(model.roots.first)
        XCTAssertEqual(row.root.path, FolderWatcher.canonicalPath(of: folder))
        XCTAssertEqual(row.items, 4)
        XCTAssertEqual(row.totalSize, 1000)
        XCTAssertTrue(model.volumes.contains { $0.path == "/" }, "mounted volumes are listed")
        XCTAssertEqual(model.status, .idle)
    }

    func testExclusionsRescanTheRoot() async throws {
        try await waitUntil("scanned") { model.roots.first?.root.scannedAt != nil }
        let skip = FolderWatcher.canonicalPath(of: folder.appendingPathComponent("Skip"))
        try model.addExclusion(skip, to: XCTUnwrap(model.roots.first))
        try await waitUntil("excluded") { model.roots.first?.totalSize == 100 }
        XCTAssertEqual(model.roots.first?.root.exclusions, [skip])

        try model.removeExclusion(skip, from: XCTUnwrap(model.roots.first))
        try await waitUntil("included again") { model.roots.first?.totalSize == 1000 }
    }

    func testRebuildKeepsTheSameTotals() async throws {
        try await waitUntil("scanned") { model.roots.first?.root.scannedAt != nil }
        let before = try XCTUnwrap(model.roots.first?.root.scannedAt)
        try model.rebuild(XCTUnwrap(model.roots.first))
        try await waitUntil("rebuilt") { (model.roots.first?.root.scannedAt ?? before) > before }
        XCTAssertEqual(model.roots.first?.totalSize, 1000)
    }
}
