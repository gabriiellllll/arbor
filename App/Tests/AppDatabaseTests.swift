@testable import Arbor
import XCTest

final class AppDatabaseTests: XCTestCase {
    private var database: AppDatabase!
    private let places = ["/Users/test", "/Users/test/Desktop", "/Applications"].map { URL(fileURLWithPath: $0) }

    override func setUpWithError() throws {
        database = try AppDatabase.inMemory()
    }

    func testFirstLaunchSeedsAWorkspaceAndFavorites() throws {
        try database.seedIfEmpty(defaultWorkspaceName: "Main", favorites: places)
        XCTAssertEqual(try database.workspaces().map(\.name), ["Main"])
        XCTAssertEqual(try database.currentWorkspaceID(), try database.workspaces().first?.id)
        let favorites = try database.favorites()
        XCTAssertEqual(favorites.map(\.path), places.map(\.path))
        XCTAssertEqual(favorites.map(\.colorIndex), [0, 1, 2])
    }

    func testSeedingTwiceChangesNothing() throws {
        try database.seedIfEmpty(defaultWorkspaceName: "Main", favorites: places)
        try database.seedIfEmpty(defaultWorkspaceName: "Other", favorites: [])
        XCTAssertEqual(try database.workspaces().count, 1)
        XCTAssertEqual(try database.favorites().count, 3)
    }

    func testWorkspacesAreCreatedRenamedAndDeletedInOrder() throws {
        let first = try database.createWorkspace(name: "One")
        let second = try database.createWorkspace(name: "Two")
        try database.renameWorkspace(second.id, to: "Deux")
        XCTAssertEqual(try database.workspaces().map(\.name), ["One", "Deux"])
        try database.deleteWorkspace(first.id)
        XCTAssertEqual(try database.workspaces().map(\.name), ["Deux"])
    }

    func testDeletingTheCurrentWorkspaceSelectsAnother() throws {
        let first = try database.createWorkspace(name: "One")
        let second = try database.createWorkspace(name: "Two")
        try database.setCurrentWorkspace(first.id)
        try database.deleteWorkspace(first.id)
        XCTAssertEqual(try database.currentWorkspaceID(), second.id)
    }

    func testCanvasIsStoredPerWorkspace() throws {
        let first = try database.createWorkspace(name: "One")
        let second = try database.createWorkspace(name: "Two")
        try database.saveCanvas(Data("one".utf8), for: first.id)
        XCTAssertEqual(try database.canvas(for: first.id), Data("one".utf8))
        XCTAssertNil(try database.canvas(for: second.id))
    }

    func testFavoritesAddMoveRecolorAndRemove() throws {
        let home = try database.addFavorite(places[0], colorIndex: nil)
        let desktop = try database.addFavorite(places[1], colorIndex: nil)
        XCTAssertNil(try database.addFavorite(places[0], colorIndex: nil), "no duplicates")
        XCTAssertEqual(try database.favorites().map(\.colorIndex), [0, 1], "least used color by default")

        try database.moveFavorite(XCTUnwrap(desktop).id, to: 0)
        XCTAssertEqual(try database.favorites().map(\.path), [places[1].path, places[0].path])

        try database.setFavoriteColor(XCTUnwrap(home).id, to: 5)
        XCTAssertEqual(try database.favorites().last?.colorIndex, 5)

        try database.removeFavorite(XCTUnwrap(home).id)
        XCTAssertEqual(try database.favorites().map(\.path), [places[1].path])
    }

    func testSharesAreRememberedRenamedAndForgotten() throws {
        let nas = try XCTUnwrap(URL(string: "smb://nas.local/Media"))
        try database.rememberShare(nas, name: "Media")
        try database.rememberShare(XCTUnwrap(URL(string: "smb://nas.local/archive")), name: "archive")
        try database.rememberShare(nas, name: "Movies")
        XCTAssertEqual(try database.shares().map(\.name), ["archive", "Movies"])
        try database.forgetShare(nas)
        XCTAssertEqual(try database.shares().map(\.url.absoluteString), ["smb://nas.local/archive"])
    }

    func testOnDiskDatabaseKeepsData() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("arbor-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try AppDatabase.open(at: url).createWorkspace(name: "Kept")
        XCTAssertEqual(try AppDatabase.open(at: url).workspaces().map(\.name), ["Kept"])
    }
}
