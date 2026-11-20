import AppKit
import CanvasKit
import IndexKit
import SwiftUI

/// Owns the canvas and its folder panels. Selecting folders in a panel opens them as child
/// panels linked by branches; selecting something else replaces those branches. Panels are
/// arranged by the current layout (see `CanvasViewController+Layout`), and two folders can be
/// compared side by side (see `CanvasViewController+Compare`).
@MainActor
final class CanvasViewController: NSViewController {
    static let panelSize = CGSize(width: 380, height: 420)
    static let layoutDefaultsKey = "canvasLayout"

    let canvasView = CanvasView()

    /// The single selected item, for the inspector.
    var onInspectedItemChange: ((FolderItem?) -> Void)?
    var onViewportChange: (() -> Void)?

    /// Where the layout choice is saved (tests pass a throwaway domain).
    let defaults: UserDefaults

    var layout: CanvasLayout {
        didSet { layoutDidChange(from: oldValue) }
    }

    var tree = PanelTree<URL>()
    var panels: [PanelID: FolderPanelController] = [:]
    /// Palette index of each root; descendants use their root's color.
    var rootColors: [PanelID: Int] = [:]
    var compare: CompareSession?
    /// Positions of the manual layout, restored when switching back to it.
    var manualFrames: [PanelID: CGRect] = [:]
    /// Set while a layout switch keeps the current positions instead of restoring saved ones.
    var keepsFramesOnManualSwitch = false
    /// Set while mirroring a selection to the compared panel, so it is not mirrored back.
    var isMirroringSelection = false
    let animator = FrameAnimator()
    /// Restoring a workspace: folder names to select in each folder once it loads (which
    /// reopens its branches), and saved panel frames, by folder path.
    var pendingSelections: [String: [String]] = [:]
    var pendingFrames: [String: CGRect] = [:]
    /// "Add to Favorites" was chosen in a panel.
    var onAddFavorites: (([URL]) -> Void)?
    /// Folders opened, for Back and Forward.
    var history = NavigationHistory<String>()
    /// Set while Back or Forward reopens a folder, so it is not recorded again.
    var isNavigatingHistory = false

    var activePanel: PanelID? {
        didSet {
            for (id, panel) in panels {
                panel.panelView.isActive = id == activePanel
            }
        }
    }

    private let banner = NSHostingView(rootView: LimitedModeBanner())
    private var canvasTop: NSLayoutConstraint?

    private lazy var watcher = FolderWatcher { [weak self] changes in
        Task { @MainActor in self?.foldersChanged(changes) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = defaults.string(forKey: Self.layoutDefaultsKey).flatMap(CanvasLayout.init(rawValue:)) ?? .treeRight
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        // The canvas starts below the toolbar so panels are never hidden under it.
        view = NSView()
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(canvasView)
        banner.translatesAutoresizingMaskIntoConstraints = false
        banner.isHidden = true
        banner.setAccessibilityIdentifier("limitedModeBanner")
        view.addSubview(banner)
        let canvasTop = canvasView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor)
        self.canvasTop = canvasTop
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            banner.heightAnchor.constraint(equalToConstant: LimitedModeBanner.height),
            canvasTop,
            canvasView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        canvasView.onViewportChange = { [weak self] in self?.onViewportChange?() }
    }

    /// Shows or hides the limited mode banner above the canvas.
    func setLimitedMode(_ limited: Bool) {
        banner.isHidden = !limited
        canvasTop?.constant = limited ? LimitedModeBanner.height : 0
    }

    // MARK: - Opening

    /// Opens `url` as a root panel in `colorIndex` (or the least used color), or reveals it if
    /// it is already open as a root.
    func openRoot(_ url: URL, colorIndex: Int? = nil) {
        if let existing = tree.roots
            .first(where: { tree[$0]?.content.standardizedFileURL == url.standardizedFileURL && !isCompared($0) })
        {
            activate(existing, reveal: true)
            recordVisit(existing)
            return
        }
        let id = addRoot(url, colorIndex: colorIndex)
        recordVisit(id)
        activate(id, reveal: layout == .manual)
        applyLayout(revealing: id)
    }

    /// Adds a root panel near the top-left of the visible area.
    func addRoot(_ url: URL, colorIndex: Int?) -> PanelID {
        let visible = canvasView.visibleCanvasRect
        let origin = CGPoint(
            x: visible.minX + 40 / canvasView.magnification,
            y: visible.minY + 40 / canvasView.magnification
        )
        let frame = PanelPlacement.frame(at: origin, size: Self.panelSize, avoiding: tree.panels.values.map(\.frame))
        let id = tree.addRoot(content: url, frame: frame)
        rootColors[id] = colorIndex ?? BranchPalette.nextIndex(used: Array(rootColors.values))
        addPanel(id, url: url, frame: frame)
        return id
    }

    private func addPanel(_ id: PanelID, url: URL, frame proposed: CGRect) {
        let frame = pendingFrames.removeValue(forKey: url.path) ?? proposed
        tree.setFrame(frame, for: id)
        let panel = FolderPanelController(url: url, frame: frame)
        panel.onAddFavorites = { [weak self] urls in self?.onAddFavorites?(urls) }
        panel.tint = color(of: id)
        panel.onSelectionChange = { [weak self] items in self?.selectionChanged(in: id, to: items) }
        panel.onRowsMoved = { [weak self] in self?.updateBranches() }
        panel.onClose = { [weak self] in self?.closePanel(id) }
        panel.panelView.onActivate = { [weak self] in self?.activate(id, reveal: false) }
        panel.panelView.onFrameChanging = { [weak self] in self?.panelDragged(id) }
        panel.panelView.onFrameChanged = { [weak self] in self?.panelDragEnded(id) }
        panels[id] = panel
        canvasView.documentView.addSubview(panel.panelView)
        panel.reload()
        updateWatchedFolders()
    }

    func activate(_ id: PanelID, reveal: Bool) {
        activePanel = id
        guard let panel = panels[id] else { return }
        onInspectedItemChange?(panel.selectedItems.count == 1 ? panel.selectedItems.first : nil)
        if reveal {
            canvasView.reveal(panel.panelView.frame)
        }
    }

    func color(of id: PanelID) -> NSColor {
        BranchPalette.color(at: tree.chain(to: id).first.flatMap { rootColors[$0] } ?? 0)
    }

    // MARK: - Selection → child panels

    private func selectionChanged(in id: PanelID, to items: [FolderItem]) {
        guard let parent = panels[id] else { return }
        if let names = pendingSelections.removeValue(forKey: parent.url.path), !parent.items.isEmpty {
            // Restoring: selecting the saved folders reopens their branches.
            parent.select(names: Set(names))
            return
        }
        var folders = items.filter(\.isFolder)
        if isCompared(id) {
            // ponytail: compared folders are followed one path at a time; trees would need a compare-tree layout.
            folders = Array(folders.prefix(1))
        }
        var occupied = tree.panels.values.map(\.frame)
        let result = tree.syncChildren(of: id, to: folders.map { ($0.name, $0.url) }) { parentPanel, key in
            let sourceY = parent.branchSourceY(forName: key) ?? parentPanel.frame.minY
            let frame = PanelPlacement.childFrame(
                parent: parentPanel.frame, sourceY: sourceY, size: Self.panelSize, avoiding: occupied
            )
            occupied.append(frame)
            return frame
        }
        removePanels(result.removed)
        for added in result.added {
            if let panel = tree[added] {
                addPanel(added, url: panel.content, frame: panel.frame)
            }
        }
        // Reloads also report selection: only the active panel drives the inspector.
        if id == activePanel {
            onInspectedItemChange?(items.count == 1 ? items.first : nil)
        }
        if isCompared(id) {
            mirrorSelection(from: id, names: Set(folders.map(\.name)))
            updateComparisonMarks()
        }
        if let last = result.added.last {
            recordVisit(last)
        }
        if result.added.isEmpty, result.removed.isEmpty {
            updateBranches()
        } else {
            applyLayout(revealing: result.added.last)
        }
    }

    private func closePanel(_ id: PanelID) {
        guard let panel = tree[id] else { return }
        if let parentID = panel.parent, let parent = panels[parentID], let key = panel.sourceKey {
            // Closing a child is deselecting its row in the parent.
            parent.deselect(key)
            return
        }
        if let compare, compare.contains(root: id) {
            endComparison()
            return
        }
        rootColors[id] = nil
        removePanels(tree.remove(id))
        applyLayout(revealing: nil)
    }

    func removePanels(_ ids: [PanelID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            panels.removeValue(forKey: id)?.panelView.removeFromSuperview()
            manualFrames[id] = nil
        }
        updateWatchedFolders()
    }

    // MARK: - Branches

    func updateBranches() {
        var branches: [PanelID: (curve: BranchCurve, color: NSColor)] = [:]
        for panel in tree.panels.values {
            guard let parentID = panel.parent, let parent = tree[parentID], let key = panel.sourceKey,
                  let sourceY = panels[parentID]?.branchSourceY(forName: key) else { continue }
            let curve = BranchAnchors.curve(parent: parent.frame, sourceY: sourceY, child: panel.frame)
            branches[panel.id] = (curve, color(of: panel.id))
        }
        canvasView.branchesView.setBranches(branches)
    }

    // MARK: - Live updates

    private func updateWatchedFolders() {
        watcher.watch(Set(panels.values.map(\.canonicalPath)))
    }

    private func foldersChanged(_ changes: [FolderChange]) {
        for panel in panels.values {
            let changed = changes.contains { change in
                change.path == panel.canonicalPath
                    || (change.mustRescanSubfolders && panel.canonicalPath.hasPrefix(change.path + "/"))
            }
            if changed {
                panel.reload()
            }
        }
    }
}
