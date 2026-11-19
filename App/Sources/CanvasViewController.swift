import AppKit
import CanvasKit
import IndexKit
import SwiftUI

/// Owns the canvas and its folder panels. Selecting folders in a panel opens them as child
/// panels linked by branches; selecting something else replaces those branches.
@MainActor
final class CanvasViewController: NSViewController {
    static let panelSize = CGSize(width: 420, height: 440)

    let canvasView = CanvasView()

    /// The single selected item, for the inspector.
    var onInspectedItemChange: ((FolderItem?) -> Void)?
    var onViewportChange: (() -> Void)?

    private var tree = PanelTree<URL>()
    private var panels: [PanelID: FolderPanelController] = [:]
    private var activePanel: PanelID? {
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

    /// Opens `url` as a root panel, or reveals it if it is already open as a root.
    func openRoot(_ url: URL) {
        if let existing = tree.roots
            .first(where: { tree[$0]?.content.standardizedFileURL == url.standardizedFileURL })
        {
            activate(existing, reveal: true)
            return
        }
        let visible = canvasView.visibleCanvasRect
        let origin = CGPoint(
            x: visible.minX + 40 / canvasView.magnification,
            y: visible.minY + 40 / canvasView.magnification
        )
        let frame = PanelPlacement.frame(at: origin, size: Self.panelSize, avoiding: tree.panels.values.map(\.frame))
        let id = tree.addRoot(content: url, frame: frame)
        addPanel(id, url: url, frame: frame)
        activate(id, reveal: true)
    }

    private func addPanel(_ id: PanelID, url: URL, frame: CGRect) {
        let panel = FolderPanelController(url: url, frame: frame)
        panel.onSelectionChange = { [weak self] items in self?.selectionChanged(in: id, to: items) }
        panel.onRowsMoved = { [weak self] in self?.updateBranches() }
        panel.onClose = { [weak self] in self?.closePanel(id) }
        panel.panelView.onActivate = { [weak self] in self?.activate(id, reveal: false) }
        panel.panelView.onFrameChanging = { [weak self] in self?.panelMoved(id) }
        panel.panelView.onFrameChanged = { [weak self] in self?.panelMoved(id) }
        panels[id] = panel
        canvasView.documentView.addSubview(panel.panelView)
        panel.reload()
        updateWatchedFolders()
    }

    private func activate(_ id: PanelID, reveal: Bool) {
        activePanel = id
        guard let panel = panels[id] else { return }
        onInspectedItemChange?(panel.selectedItems.count == 1 ? panel.selectedItems.first : nil)
        if reveal {
            canvasView.reveal(panel.panelView.frame)
        }
    }

    // MARK: - Selection → child panels

    private func selectionChanged(in id: PanelID, to items: [FolderItem]) {
        guard let parent = panels[id] else { return }
        let folders = items.filter(\.isFolder)
        var occupied = tree.panels.values.map(\.frame)
        let result = tree.syncChildren(of: id, to: folders.map { ($0.name, $0.url) }) { parentPanel, key in
            let sourceY = parent.branchSourceY(forName: key) ?? parentPanel.frame.minY
            let frame = PanelPlacement.childFrame(
                parent: parentPanel.frame, sourceY: sourceY, size: Self.panelSize, avoiding: occupied
            )
            occupied.append(frame)
            return frame
        }
        for removed in result.removed {
            panels.removeValue(forKey: removed)?.panelView.removeFromSuperview()
        }
        for added in result.added {
            if let panel = tree[added] {
                addPanel(added, url: panel.content, frame: panel.frame)
            }
        }
        if !result.removed.isEmpty {
            updateWatchedFolders()
        }
        updateBranches()
        activePanel = id
        onInspectedItemChange?(items.count == 1 ? items.first : nil)
        if let last = result.added.last, let frame = tree[last]?.frame {
            canvasView.reveal(frame)
        }
    }

    private func closePanel(_ id: PanelID) {
        guard let panel = tree[id] else { return }
        if let parentID = panel.parent, let parent = panels[parentID], let key = panel.sourceKey {
            // Closing a child is deselecting its row in the parent.
            parent.deselect(key)
            return
        }
        for removed in tree.remove(id) {
            panels.removeValue(forKey: removed)?.panelView.removeFromSuperview()
        }
        updateWatchedFolders()
        updateBranches()
    }

    // MARK: - Geometry

    private func panelMoved(_ id: PanelID) {
        guard let frame = panels[id]?.panelView.frame else { return }
        tree.setFrame(frame, for: id)
        updateBranches()
    }

    private func updateBranches() {
        var branches: [PanelID: (curve: BranchCurve, color: NSColor)] = [:]
        for panel in tree.panels.values {
            guard let parentID = panel.parent, let parent = tree[parentID], let key = panel.sourceKey,
                  let sourceY = panels[parentID]?.branchSourceY(forName: key) else { continue }
            let curve = BranchCurve(
                from: CGPoint(x: parent.frame.maxX, y: sourceY),
                to: CGPoint(x: panel.frame.minX, y: panel.frame.minY + PanelPlacement.titleOffset)
            )
            branches[panel.id] = (curve, .controlAccentColor)
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
