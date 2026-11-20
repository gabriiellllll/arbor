import AppKit
import FileOpsKit

/// Context menu of folder panels: add folders to favorites, toggle Finder tags.
extension FolderPanelController: NSMenuDelegate {
    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    /// What the menu acts on: the selection, or the clicked row if it is not selected.
    var contextItems: [FolderItem] {
        let clicked = mode == .list ? tableView.clickedRow : -1
        if items.indices.contains(clicked), !selectedIndexes.contains(clicked) {
            return [items[clicked]]
        }
        return selectedItems
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let targets = contextItems
        guard !targets.isEmpty else { return }
        if targets.contains(where: \.isFolder) {
            let favorite = menu.addItem(
                withTitle: String(localized: "Add to Favorites"), action: #selector(addToFavorites), keyEquivalent: ""
            )
            favorite.target = self
        }
        let tags = NSMenuItem(title: String(localized: "Tags"), action: nil, keyEquivalent: "")
        tags.submenu = tagsMenu(for: targets)
        menu.addItem(tags)
    }

    /// The system's colored tags (label 0 is "None"), checked when all targets have them.
    private func tagsMenu(for targets: [FolderItem]) -> NSMenu {
        let menu = NSMenu()
        let current = targets.map { Set((try? FinderTags.tags(of: $0.url)) ?? []) }
        let workspace = NSWorkspace.shared
        for (index, name) in workspace.fileLabels.enumerated() where index > 0 {
            let item = menu.addItem(withTitle: name, action: #selector(toggleTag(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.image = TagColors.dotImage(TagColors.color(for: name))
            let count = current.filter { $0.contains(name) }.count
            item.state = count == current.count ? .on : (count > 0 ? .mixed : .off)
        }
        return menu
    }

    @objc private func addToFavorites() {
        onAddFavorites?(contextItems.filter(\.isFolder).map(\.url))
    }

    @objc private func toggleTag(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        do {
            try FinderTags.toggle(name, on: contextItems.map(\.url))
        } catch {
            NSApp.presentError(error)
        }
        tableView.reloadData(
            forRowIndexes: IndexSet(integersIn: 0 ..< tableView.numberOfRows), columnIndexes: IndexSet(integer: 0)
        )
    }
}
