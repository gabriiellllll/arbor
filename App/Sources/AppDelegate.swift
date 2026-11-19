import AppKit

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

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = MainMenu.make()
        let controller = MainWindowController()
        controller.showWindow(nil)
        windowController = controller
        NSApp.activate()
        do {
            if let fixture = try UITestFixture.makeIfRequested() {
                controller.openFolder(fixture)
            }
        } catch {
            NSApp.presentError(error)
        }
    }

    func applicationDidBecomeActive(_: Notification) {
        // UI tests run on a fixture folder and must not be blocked by the onboarding sheet.
        windowController?.checkFullDiskAccess(showOnboarding: !UITestFixture.isActive)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}
