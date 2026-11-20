import AppKit
import FileOpsKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    /// Unit tests run inside the app: they build their own controllers and must not touch the
    /// user's data, so the app then opens no window.
    private static var isHostingUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = MainMenu.make()
        guard !Self.isHostingUnitTests else { return }
        var fixture: URL?
        do {
            fixture = try UITestFixture.makeIfRequested()
        } catch {
            NSApp.presentError(error)
        }
        let controller = MainWindowController(
            database: openDatabase(favorites: fixture.map { [$0] }),
            runner: FileOperationRunner(trash: fixture.map(UITestFixture.trash(in:)) ?? FileOperationRunner.systemTrash)
        )
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate()
        if let fixture {
            controller.openFolder(fixture)
        }
    }

    func applicationDidBecomeActive(_: Notification) {
        // UI tests run on a fixture folder and must not be blocked by the onboarding sheet.
        windowController?.checkFullDiskAccess(showOnboarding: !UITestFixture.isActive)
    }

    func applicationWillTerminate(_: Notification) {
        windowController?.saveWorkspace()
    }

    /// The app database, seeded on first launch with `favorites` (default: the standard user
    /// folders). UI tests get a throwaway in-memory one.
    private func openDatabase(favorites: [URL]?) -> AppDatabase {
        do {
            let database = UITestFixture.isActive ? try AppDatabase.inMemory() : try AppDatabase.openDefault()
            let manager = FileManager.default
            let places = favorites ?? [manager.homeDirectoryForCurrentUser]
                + [.desktopDirectory, .documentDirectory, .downloadsDirectory]
                .compactMap { manager.urls(for: $0, in: .userDomainMask).first }
                + [URL(fileURLWithPath: "/Applications", isDirectory: true)]
            try database.seedIfEmpty(defaultWorkspaceName: String(localized: "My Workspace"), favorites: places)
            return database
        } catch {
            NSApp.presentError(error)
            // ponytail: falls back to a session-only database; data is lost on quit in that case.
            return (try? AppDatabase.inMemory()) ?? { fatalError("SQLite unavailable: \(error)") }()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
