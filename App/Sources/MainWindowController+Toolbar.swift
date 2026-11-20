import AppKit
import CanvasKit

/// The main toolbar: navigation, open folder, hand tool, zoom, layout, background, panes.
extension MainWindowController: NSToolbarDelegate {
    enum Item {
        static let hand = NSToolbarItem.Identifier("hand")
        static let zoomOut = NSToolbarItem.Identifier("zoomOut")
        static let zoomLevel = NSToolbarItem.Identifier("zoomLevel")
        static let zoomIn = NSToolbarItem.Identifier("zoomIn")
        static let zoomReset = NSToolbarItem.Identifier("zoomReset")
        static let background = NSToolbarItem.Identifier("background")
        static let layout = NSToolbarItem.Identifier("layout")
        static let back = NSToolbarItem.Identifier("back")
        static let forward = NSToolbarItem.Identifier("forward")
        static let openFolder = NSToolbarItem.Identifier("openFolder")
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator, Item.back, Item.forward, Item.openFolder, .flexibleSpace,
            Item.hand, Item.zoomOut, Item.zoomLevel, Item.zoomIn, Item.zoomReset, Item.layout, Item.background,
            .inspectorTrackingSeparator, .flexibleSpace, .toggleInspector,
        ]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar) + [.space]
    }

    func toolbar(
        _: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar _: Bool
    ) -> NSToolbarItem? {
        if let spec = buttonItems[identifier] {
            return button(identifier, spec.label, spec.symbol, spec.action)
        }
        switch identifier {
        case Item.hand: return handToolItem()
        case Item.zoomLevel: return zoomLevelItem()
        case Item.background: return backgroundItem()
        case Item.layout: return layoutItem()
        default: return nil
        }
    }

    private struct ButtonSpec {
        let label: String
        let symbol: String
        let action: Selector
    }

    /// Plain toolbar buttons.
    private var buttonItems: [NSToolbarItem.Identifier: ButtonSpec] {
        [
            Item.back: ButtonSpec(
                label: String(localized: "Back"),
                symbol: "chevron.left",
                action: #selector(goBack(_:))
            ),
            Item.forward: ButtonSpec(
                label: String(localized: "Forward"), symbol: "chevron.right", action: #selector(goForward(_:))
            ),
            Item.openFolder: ButtonSpec(
                label: String(localized: "Open Folder"), symbol: "folder.badge.plus",
                action: #selector(openDocument(_:))
            ),
            Item.zoomOut: ButtonSpec(
                label: String(localized: "Zoom Out"), symbol: "minus.magnifyingglass", action: #selector(zoomOut(_:))
            ),
            Item.zoomIn: ButtonSpec(
                label: String(localized: "Zoom In"), symbol: "plus.magnifyingglass", action: #selector(zoomIn(_:))
            ),
            Item.zoomReset: ButtonSpec(
                label: String(localized: "Actual Size"), symbol: "1.magnifyingglass", action: #selector(resetZoom(_:))
            ),
        ]
    }

    private func button(
        _ identifier: NSToolbarItem.Identifier, _ label: String, _ symbol: String, _ action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.action = action
        item.isBordered = true
        return item
    }

    private func handToolItem() -> NSToolbarItem {
        let label = String(localized: "Hand Tool")
        handButton.setButtonType(.pushOnPushOff)
        handButton.bezelStyle = .toolbar
        handButton.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: label)
        handButton.target = self
        handButton.action = #selector(toggleHandTool(_:))
        let item = NSToolbarItem(itemIdentifier: Item.hand)
        item.label = label
        item.toolTip = label
        item.view = handButton
        return item
    }

    private func zoomLevelItem() -> NSToolbarItem {
        zoomLabel.alignment = .center
        zoomLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        zoomLabel.widthAnchor.constraint(equalToConstant: 48).isActive = true
        zoomLabel.setAccessibilityIdentifier("zoomLevel")
        let item = NSToolbarItem(itemIdentifier: Item.zoomLevel)
        item.label = String(localized: "Zoom")
        item.view = zoomLabel
        return item
    }

    private func layoutItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: Item.layout)
        item.label = String(localized: "Layout")
        item.toolTip = String(localized: "Layout")
        item.image = NSImage(
            systemSymbolName: "point.3.connected.trianglepath.dotted",
            accessibilityDescription: item.label
        )
        item.menu = MainMenu.layoutMenu()
        item.showsIndicator = true
        return item
    }

    private func backgroundItem() -> NSToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: Item.background)
        item.label = String(localized: "Background")
        item.toolTip = String(localized: "Background")
        item.image = NSImage(systemSymbolName: "circle.grid.3x3", accessibilityDescription: item.label)
        item.menu = MainMenu.backgroundMenu()
        item.showsIndicator = true
        return item
    }
}
