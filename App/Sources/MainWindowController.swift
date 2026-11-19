import AppKit

/// Hosts the main window. Sidebar, canvas and inspector arrive in phase 1.
@MainActor
final class MainWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Arbor")
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.setFrameAutosaveName("MainWindow")
        window.center()
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
