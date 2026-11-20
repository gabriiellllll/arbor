import AppKit
import CanvasKit
import FileOpsKit

/// File commands on the canvas. A selection can span panels: a plain click starts a new one,
/// ⌘- or ⇧-click keeps the other panels' selections. Selected folders whose branch is open only
/// mark the path, so they are targets only in the active panel.
extension CanvasViewController {
    /// Folder names whose child panel is open, in panel `id`.
    private func branchNames(of id: PanelID) -> Set<String> {
        Set(tree.children(of: id).compactMap(\.sourceKey))
    }

    /// Items the file commands act on, without items inside another target.
    var operationTargets: [URL] {
        var urls: [URL] = []
        for (id, panel) in panels {
            let branches = branchNames(of: id)
            let items = id == activePanel ? panel.selectedItems : panel.selectedItems
                .filter { !branches.contains($0.name) }
            urls += items.map(\.url)
        }
        let paths = Set(urls.map(\.standardizedFileURL.path))
        return urls
            .filter { url in !paths.contains { url.standardizedFileURL.path.hasPrefix($0 + "/") } }
            .sorted { $0.path < $1.path }
    }

    /// The folder of the active panel: where pasted items go.
    var activeFolder: URL? {
        activePanel.flatMap { panels[$0]?.url }
    }

    /// A plain click in panel `id`: other panels keep only their branch folders selected.
    func clearLooseSelections(keeping id: PanelID) {
        for (otherID, panel) in panels where otherID != id {
            let selected = Set(panel.selectedItems.map(\.name))
            let kept = selected.intersection(branchNames(of: otherID))
            if kept != selected {
                panel.select(names: kept)
            }
        }
    }

    func panelClicked(_ id: PanelID) {
        activate(id, reveal: false)
        let extending = NSApp.currentEvent
            .map { $0.modifierFlags.contains(.command) || $0.modifierFlags.contains(.shift) }
        if extending != true {
            clearLooseSelections(keeping: id)
        }
    }

    // MARK: - Commands

    func copySelectionToPasteboard() {
        let targets = operationTargets
        guard !targets.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(targets as [NSURL])
    }

    /// Copies (or moves) the files on the pasteboard into the active panel's folder.
    func pasteFiles(moving: Bool) {
        guard let folder = activeFolder else { return }
        let urls = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return }
        transfer(urls, into: folder, copying: !moving)
    }

    func trashSelection() {
        let targets = operationTargets
        guard !targets.isEmpty else { return }
        onPerform?(FileOperation(kind: .trash, sources: targets), String(localized: "Move to Trash"))
    }

    func renameSelection() {
        activePanel.flatMap { panels[$0] }?.beginRename()
    }

    func transfer(_ urls: [URL], into folder: URL, copying: Bool) {
        let kind: FileOperationKind = copying ? .copy(into: folder) : .move(into: folder)
        onPerform?(
            FileOperation(kind: kind, sources: urls),
            copying ? String(localized: "Copy") : String(localized: "Move")
        )
    }

    func rename(_ url: URL, to name: String) {
        onPerform?(FileOperation(kind: .rename(newName: name), sources: [url]), String(localized: "Rename"))
    }
}
