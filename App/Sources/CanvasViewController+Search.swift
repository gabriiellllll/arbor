import AppKit
import CanvasKit
import IndexKit

/// What a panel shows: a folder, or search results from the index.
enum PanelContent: Equatable {
    case folder(URL)
    case search
}

/// Search panels: roots of the canvas tree (laid out like folder roots) whose results can
/// open their folder chain.
extension CanvasViewController {
    static let searchPanelSize = CGSize(width: 560, height: 420)

    var activeSearch: SearchPanelController? {
        activePanel.flatMap { searchPanels[$0] }
    }

    /// Searches for `text` in the active search panel, or in a new one.
    func search(text: String) {
        if let search = activeSearch {
            search.setText(text)
        } else if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            openSearch(SearchSpec(text: text))
        }
    }

    func openSearch(_ spec: SearchSpec) {
        let id = addSearch(spec, colorIndex: nil)
        activate(id, reveal: layout == .manual)
        applyLayout(revealing: id)
    }

    func addSearch(_ spec: SearchSpec, colorIndex: Int?) -> PanelID {
        let (id, proposed) = addRoot(.search, size: Self.searchPanelSize, colorIndex: colorIndex)
        let panel = SearchPanelController(
            spec: spec, frame: proposed, tags: index?.tagNames() ?? [], roots: index?.roots() ?? []
        )
        panel.search = { [weak self] query in await self?.index?.search(query) ?? [] }
        panel.tint = color(of: id)
        panel.onClose = { [weak self] in self?.closePanel(id) }
        panel.onReveal = { [weak self] path in self?.reveal(path: path) }
        panel.panelView.onActivate = { [weak self] in self?.panelClicked(id) }
        panel.panelView.onFrameChanging = { [weak self] in self?.panelDragged(id) }
        panel.panelView.onFrameChanged = { [weak self] in self?.panelDragEnded(id) }
        searchPanels[id] = panel
        canvasView.documentView.addSubview(panel.panelView)
        panel.refresh()
        return id
    }

    // ponytail: panels hide hidden items, so a chain through a hidden folder stops there.
    /// Opens the folders leading to `path` (canonical, as the index has it) down to the item
    /// itself, selected: from the deepest open root holding it, else from the home folder or
    /// the volume's root.
    func reveal(path: String) {
        let url = URL(fileURLWithPath: path)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let volume = (try? url.resourceValues(forKeys: [.volumeURLKey]).volume) ?? URL(fileURLWithPath: "/")
        let openRoots = tree.roots.filter { !isCompared($0) }.compactMap { panels[$0] }
            .map { (url: $0.url, canonical: $0.canonicalPath) }
        let bases = openRoots.sorted { $0.canonical.count > $1.canonical.count }
            + [home, volume].map { (url: $0, canonical: FolderWatcher.canonicalPath(of: $0)) }
        guard let (base, names) = bases.lazy.compactMap({ base in
            Self.names(of: path, below: base.canonical).map { (base.url, $0) }
        }).first else { return }
        var folder = base
        for name in names {
            pendingSelections[folder.path] = [name]
            folder.appendPathComponent(name, isDirectory: true)
        }
        openRoot(base)
        applyPendingSelections()
    }

    /// The names leading from `base` down to `path`, if `path` is inside it.
    static func names(of path: String, below base: String) -> [String]? {
        let all = URL(fileURLWithPath: path).pathComponents
        let prefix = URL(fileURLWithPath: base).pathComponents
        return all.count > prefix.count && all.starts(with: prefix) ? Array(all.dropFirst(prefix.count)) : nil
    }

    /// Panels already loaded do not reload: select their pending names now. Each selection
    /// opens or keeps a child, which may itself be loaded already.
    private func applyPendingSelections() {
        var progressed = true
        while progressed {
            progressed = false
            for panel in panels.values where !panel.items.isEmpty {
                if let names = pendingSelections.removeValue(forKey: panel.url.path) {
                    panel.select(names: Set(names))
                    progressed = true
                }
            }
        }
    }
}
