import AppKit
import CanvasKit
import FileOpsKit
import SwiftUI

/// The main window: sidebar, canvas, inspector and toolbar. Menu and toolbar commands land
/// here through the responder chain, whatever has focus.
@MainActor
final class MainWindowController: NSWindowController, NSMenuItemValidation {
    private static let backgroundDefaultsKey = "canvasBackground"

    private let split: MainSplitViewController
    let operations: FileOperationsController
    let index: IndexService?
    private var settings: SettingsWindowController?
    let operationsButton = NSButton()
    let operationsPopover = NSPopover()
    let zoomLabel = NSTextField(labelWithString: "100 %")
    let handButton = NSButton()
    weak var searchItem: NSSearchToolbarItem?

    private let onboarding = AccessOnboarding(defaults: .standard)
    private var onboardingSheet: NSViewController?

    var canvas: CanvasViewController {
        split.canvas
    }

    init(database: AppDatabase, runner: FileOperationRunner, index: IndexService?) {
        split = MainSplitViewController(database: database)
        operations = FileOperationsController(runner: runner)
        self.index = index
        let window = MainWindow(
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
        setUpFileOperations(in: window)
        // UI tests run without the network (and its Local Network prompt).
        if !UITestFixture.isActive {
            split.sidebar.browseServers()
        }
        if let index {
            canvas.sizeLookup = { [weak index] path in index?.sizes(ofFolder: path) ?? [:] }
            canvas.index = index
            split.sidebar.tagNames = { [weak index] in index?.tagNames() ?? [] }
            split.sidebar.index = index
            index.onChange = { [weak self] _ in
                self?.canvas.indexChanged()
                self?.split.sidebar.indexChanged()
                self?.refreshSettings()
            }
            index.onStatus = { [weak self] _ in self?.refreshSettings() }
            index.start()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func openFolder(_ url: URL) {
        canvas.openRoot(url)
    }

    /// Saves the current workspace (on quit).
    func saveWorkspace() {
        split.saveWorkspace()
    }

    @objc func newWorkspace(_: Any?) {
        split.createWorkspace()
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

    @objc func goBack(_: Any?) {
        canvas.goBack()
    }

    @objc func goForward(_: Any?) {
        canvas.goForward()
    }

    @objc func showSettings(_: Any?) {
        guard let index else { return }
        let controller = settings ?? SettingsWindowController(index: index)
        settings = controller
        controller.model.refresh()
        controller.showWindow(nil)
        controller.window?.center()
    }

    private func refreshSettings() {
        if let settings, settings.isVisible {
            settings.model.refresh()
        }
    }

    @objc func toggleSizeBars(_: Any?) {
        canvas.showsSizeBars.toggle()
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
        case #selector(showSettings(_:)):
            return index != nil
        case #selector(toggleSizeBars(_:)):
            item.state = canvas.showsSizeBars ? .on : .off
        case #selector(goBack(_:)):
            return canvas.history.canGoBack
        case #selector(goForward(_:)):
            return canvas.history.canGoForward
        case #selector(setCanvasBackground(_:)):
            item.state = CanvasBackground.allCases.firstIndex(of: canvas.canvasView.background) == item.tag ? .on : .off
        case #selector(toggleHandTool(_:)):
            item.state = canvas.canvasView.isHandToolActive ? .on : .off
        default:
            return validateFileCommand(item)
        }
        return true
    }

    private func updateZoomLabel() {
        zoomLabel.stringValue = Double(canvas.canvasView.targetMagnification)
            .formatted(.percent.precision(.fractionLength(0)))
    }
}
