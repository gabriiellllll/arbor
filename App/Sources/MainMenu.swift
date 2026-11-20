import AppKit

/// Builds the application main menu.
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: String(localized: "About Arbor"),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(localized: "Hide Arbor"),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: String(localized: "Quit Arbor"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        main.addItem(submenu: appMenu)
        main.addItem(submenu: fileMenu())
        main.addItem(submenu: viewMenu())
        main.addItem(submenu: goMenu())

        let windowMenu = NSMenu(title: String(localized: "Window"))
        windowMenu.addItem(
            withTitle: String(localized: "Minimize"),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: String(localized: "Close"),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        main.addItem(submenu: windowMenu)
        NSApp.windowsMenu = windowMenu

        return main
    }
}

extension MainMenu {
    static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "File"))
        let workspace = menu.addItem(
            withTitle: String(localized: "New Workspace"),
            action: #selector(MainWindowController.newWorkspace(_:)),
            keyEquivalent: "n"
        )
        workspace.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(
            withTitle: String(localized: "Open Folder…"),
            action: #selector(MainWindowController.openDocument(_:)),
            keyEquivalent: "o"
        )
        return menu
    }

    static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "View"))
        menu.addItem(
            withTitle: String(localized: "Zoom In"), action: #selector(MainWindowController.zoomIn(_:)),
            keyEquivalent: "+"
        )
        menu.addItem(
            withTitle: String(localized: "Zoom Out"), action: #selector(MainWindowController.zoomOut(_:)),
            keyEquivalent: "-"
        )
        menu.addItem(
            withTitle: String(localized: "Actual Size"), action: #selector(MainWindowController.resetZoom(_:)),
            keyEquivalent: "0"
        )
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Hand Tool"), action: #selector(MainWindowController.toggleHandTool(_:)),
            keyEquivalent: ""
        )
        let layout = NSMenuItem(title: String(localized: "Layout"), action: nil, keyEquivalent: "")
        layout.submenu = layoutMenu()
        menu.addItem(layout)
        menu.addItem(
            withTitle: String(localized: "Compare Side by Side"),
            action: #selector(MainWindowController.compareSideBySide(_:)),
            keyEquivalent: ""
        )
        let background = NSMenuItem(title: String(localized: "Background"), action: nil, keyEquivalent: "")
        background.submenu = backgroundMenu()
        menu.addItem(background)
        menu.addItem(.separator())
        let sidebar = menu.addItem(
            withTitle: String(localized: "Show Sidebar"), action: #selector(NSSplitViewController.toggleSidebar(_:)),
            keyEquivalent: "s"
        )
        sidebar.keyEquivalentModifierMask = [.command, .control]
        let inspector = menu.addItem(
            withTitle: String(localized: "Show Inspector"),
            action: #selector(NSSplitViewController.toggleInspector(_:)),
            keyEquivalent: "i"
        )
        inspector.keyEquivalentModifierMask = [.command, .option]
        return menu
    }

    static func goMenu() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Go"))
        menu.addItem(
            withTitle: String(localized: "Back"),
            action: #selector(MainWindowController.goBack(_:)),
            keyEquivalent: "["
        )
        menu.addItem(
            withTitle: String(localized: "Forward"), action: #selector(MainWindowController.goForward(_:)),
            keyEquivalent: "]"
        )
        return menu
    }

    /// One item per layout (⌘1 to ⌘4); the tag is the layout's index in `CanvasLayout.allCases`.
    static func layoutMenu() -> NSMenu {
        let titles = [
            String(localized: "Tree to the Right"), String(localized: "Tree Downward"),
            String(localized: "Star"), String(localized: "Manual"),
        ]
        let menu = NSMenu(title: String(localized: "Layout"))
        for (index, title) in titles.enumerated() {
            let item = menu.addItem(
                withTitle: title, action: #selector(MainWindowController.setCanvasLayout(_:)),
                keyEquivalent: "\(index + 1)"
            )
            item.tag = index
        }
        return menu
    }

    /// One item per canvas background style; the tag is the style's index.
    static func backgroundMenu() -> NSMenu {
        let titles = [
            String(localized: "Dots"), String(localized: "Grid"), String(localized: "Crosses"),
            String(localized: "Plain"),
        ]
        let menu = NSMenu(title: String(localized: "Background"))
        for (index, title) in titles.enumerated() {
            let item = menu.addItem(
                withTitle: title, action: #selector(MainWindowController.setCanvasBackground(_:)), keyEquivalent: ""
            )
            item.tag = index
        }
        return menu
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu) {
        let item = NSMenuItem()
        item.submenu = submenu
        addItem(item)
    }
}
