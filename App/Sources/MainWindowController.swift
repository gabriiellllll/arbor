import AppKit
import CanvasKit
import SwiftUI

/// The main window: sidebar, canvas, inspector and toolbar. Menu and toolbar commands land
/// here through the responder chain, whatever has focus.
@MainActor
final class MainWindowController: NSWindowController, NSToolbarDelegate, NSMenuItemValidation {
    private static let backgroundDefaultsKey = "canvasBackground"

    private let split = MainSplitViewController()
    private let zoomLabel = NSTextField(labelWithString: "100 %")
    private let handButton = NSButton()

    private let onboarding = AccessOnboarding(defaults: .standard)
    private var onboardingSheet: NSViewController?

    private var canvas: CanvasViewController {
        split.canvas
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1400, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "Arbor")
        window.identifier = NSUserInterfaceItemIdentifier("main")
        window.contentViewController = split
        window.setContentSize(NSSize(width: 1400, height: 860))
        window.setFrameAutosaveName("MainWindow")
        window.toolbarStyle = .unified
        super.init(window: window)

        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        let saved = UserDefaults.standard.string(forKey: Self.backgroundDefaultsKey)
        canvas.canvasView.background = saved.flatMap(CanvasBackground.init(rawValue:)) ?? .dots
        canvas.onViewportChange = { [weak self] in self?.updateZoomLabel() }
        updateZoomLabel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func openFolder(_ url: URL) {
        canvas.openRoot(url)
    }

    /// Checks Full Disk Access (at launch and whenever the app becomes active): limited mode
    /// banner while it is missing, onboarding the first time or when it was lost.
    func checkFullDiskAccess(showOnboarding: Bool) {
        let status = FullDiskAccess.status()
        canvas.setLimitedMode(status == .denied)
        let prompt = onboarding.prompt(for: status)
        if prompt == .none, let sheet = onboardingSheet {
            split.dismiss(sheet)
            onboardingSheet = nil
        }
        guard showOnboarding, prompt != .none, onboardingSheet == nil else { return }
        let sheet = NSHostingController(rootView: AccessOnboardingView(prompt: prompt) { [weak self] in
            self?.dismissOnboarding()
        })
        onboardingSheet = sheet
        split.presentAsSheet(sheet)
    }

    private func dismissOnboarding() {
        onboarding.dismiss()
        if let sheet = onboardingSheet {
            split.dismiss(sheet)
        }
        onboardingSheet = nil
    }

    // MARK: - Commands

    @objc func openDocument(_: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Open")
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                for url in panel.urls {
                    self?.openFolder(url)
                }
            }
        }
    }

    @objc func zoomIn(_: Any?) {
        canvas.canvasView.zoomIn()
    }

    @objc func zoomOut(_: Any?) {
        canvas.canvasView.zoomOut()
    }

    @objc func resetZoom(_: Any?) {
        canvas.canvasView.resetZoom()
    }

    @objc func toggleHandTool(_: Any?) {
        canvas.canvasView.isHandToolActive.toggle()
        handButton.state = canvas.canvasView.isHandToolActive ? .on : .off
    }

    /// The sender's tag is the index of the style in `CanvasBackground.allCases`.
    @objc func setCanvasBackground(_ sender: NSMenuItem) {
        guard CanvasBackground.allCases.indices.contains(sender.tag) else { return }
        let style = CanvasBackground.allCases[sender.tag]
        canvas.canvasView.background = style
        UserDefaults.standard.set(style.rawValue, forKey: Self.backgroundDefaultsKey)
    }

    /// The sender's tag is the index of the layout in `CanvasLayout.allCases`.
    @objc func setCanvasLayout(_ sender: NSMenuItem) {
        guard CanvasLayout.allCases.indices.contains(sender.tag) else { return }
        canvas.layout = CanvasLayout.allCases[sender.tag]
    }

    @objc func compareSideBySide(_: Any?) {
        canvas.compareSelection()
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(setCanvasLayout(_:)):
            item.state = CanvasLayout.allCases.firstIndex(of: canvas.layout) == item.tag ? .on : .off
        case #selector(compareSideBySide(_:)):
            return canvas.canCompareSelection
        case #selector(setCanvasBackground(_:)):
            item.state = CanvasBackground.allCases.firstIndex(of: canvas.canvasView.background) == item.tag ? .on : .off
        case #selector(toggleHandTool(_:)):
            item.state = canvas.canvasView.isHandToolActive ? .on : .off
        default:
            break
        }
        return true
    }

    private func updateZoomLabel() {
        zoomLabel.stringValue = Double(canvas.canvasView.targetMagnification)
            .formatted(.percent.precision(.fractionLength(0)))
    }

    // MARK: - Toolbar

    private enum Item {
        static let hand = NSToolbarItem.Identifier("hand")
        static let zoomOut = NSToolbarItem.Identifier("zoomOut")
        static let zoomLevel = NSToolbarItem.Identifier("zoomLevel")
        static let zoomIn = NSToolbarItem.Identifier("zoomIn")
        static let zoomReset = NSToolbarItem.Identifier("zoomReset")
        static let background = NSToolbarItem.Identifier("background")
        static let layout = NSToolbarItem.Identifier("layout")
        static let openFolder = NSToolbarItem.Identifier("openFolder")
    }

    func toolbarDefaultItemIdentifiers(_: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .toggleSidebar, .sidebarTrackingSeparator, Item.openFolder, .flexibleSpace,
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
        switch identifier {
        case Item.openFolder:
            button(identifier, String(localized: "Open Folder"), "folder.badge.plus", #selector(openDocument(_:)))
        case Item.hand:
            handToolItem()
        case Item.zoomOut:
            button(identifier, String(localized: "Zoom Out"), "minus.magnifyingglass", #selector(zoomOut(_:)))
        case Item.zoomIn:
            button(identifier, String(localized: "Zoom In"), "plus.magnifyingglass", #selector(zoomIn(_:)))
        case Item.zoomReset:
            button(identifier, String(localized: "Actual Size"), "1.magnifyingglass", #selector(resetZoom(_:)))
        case Item.zoomLevel:
            zoomLevelItem()
        case Item.background:
            backgroundItem()
        case Item.layout:
            layoutItem()
        default:
            nil
        }
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
