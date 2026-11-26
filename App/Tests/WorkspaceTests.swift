@testable import Arbor
import DiskKit
import XCTest

/// Workspace switching and the sidebar, on an in-memory database and a temporary folder.
@MainActor
final class WorkspaceTests: XCTestCase {
    private var folder: URL!
    private var database: AppDatabase!
    private var split: MainSplitViewController!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Sub"),
            withIntermediateDirectories: true
        )
        database = try AppDatabase.inMemory()
        try database.seedIfEmpty(defaultWorkspaceName: "Main", favorites: [folder])
        split = MainSplitViewController(database: database)
        split.loadView()
        split.viewDidLoad()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testEachWorkspaceKeepsItsCanvas() throws {
        split.canvas.openRoot(folder)
        XCTAssertEqual(split.canvas.tree.roots.count, 1)
        let main = try XCTUnwrap(split.currentWorkspace)

        split.createWorkspace()
        XCTAssertNotEqual(split.currentWorkspace, main)
        XCTAssertTrue(split.canvas.tree.roots.isEmpty, "a new workspace starts empty")
        XCTAssertEqual(try database.workspaces().count, 2)

        split.switchWorkspace(to: main)
        XCTAssertEqual(split.canvas.tree.roots.count, 1, "the first workspace gets its canvas back")
        XCTAssertEqual(try database.currentWorkspaceID(), main)
    }

    func testDeletingTheCurrentWorkspaceLoadsAnother() throws {
        let main = try XCTUnwrap(split.currentWorkspace)
        split.canvas.openRoot(folder)
        split.saveWorkspace()
        split.createWorkspace()
        let second = try XCTUnwrap(split.currentWorkspace)
        split.deleteWorkspace(second)
        XCTAssertEqual(split.currentWorkspace, main)
        XCTAssertEqual(split.canvas.tree.roots.count, 1)
    }

    func testTheLastWorkspaceIsKept() throws {
        try split.deleteWorkspace(XCTUnwrap(split.currentWorkspace))
        XCTAssertEqual(try database.workspaces().count, 1)
    }

    func testSidebarListsWorkspacesFavoritesAndLocations() {
        let sidebar = split.sidebar
        // Shared appears when this Mac has network shares mounted.
        let shared = MountedVolumes.current().contains(where: \.isNetwork)
        XCTAssertEqual(sidebar.sections.count, shared ? 4 : 3)
        XCTAssertEqual(sidebar.section(.workspaces)?.children.count, 1)
        XCTAssertEqual(sidebar.section(.favorites)?.children.count, 1)
        XCTAssertGreaterThanOrEqual(sidebar.section(.locations)?.children.count ?? 0, 1, "at least this computer")
    }

    func testAddingFavoritesFromAPanelPlacesThemInTheSidebar() throws {
        let sub = folder.appendingPathComponent("Sub", isDirectory: true)
        split.sidebar.addFavorites([sub], at: 0)
        XCTAssertEqual(try database.favorites().map(\.path), [sub.path, folder.path])
        XCTAssertEqual(split.sidebar.section(.favorites)?.children.count, 2)
    }
}
