import AppKit
import CanvasKit

/// Sidebar context menu: workspaces (new, rename, delete), favorites (color, remove),
/// locations (add to favorites). Workspace names are renamed inline.
extension SidebarViewController: NSMenuDelegate, NSTextFieldDelegate {
    /// Names of the branch palette colors, in palette order.
    static var colorNames: [String] {
        [
            String(localized: "Blue"), String(localized: "Purple"), String(localized: "Pink"),
            String(localized: "Orange"), String(localized: "Green"), String(localized: "Teal"),
            String(localized: "Indigo"), String(localized: "Brown"),
        ]
    }

    func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let node = node(at: outlineView.clickedRow) else { return }
        switch node.kind {
        case .header(.workspaces):
            add(String(localized: "New Workspace"), #selector(newWorkspace), to: menu)
        case .workspace:
            add(String(localized: "New Workspace"), #selector(newWorkspace), to: menu)
            add(String(localized: "Rename"), #selector(renameWorkspace), to: menu)
            // The last workspace cannot be deleted.
            if (section(.workspaces)?.children.count ?? 0) > 1 {
                add(String(localized: "Delete Workspace…"), #selector(deleteWorkspace), to: menu)
            }
        case let .favorite(favorite):
            let color = NSMenuItem(title: String(localized: "Color"), action: nil, keyEquivalent: "")
            color.submenu = colorMenu(selected: favorite.colorIndex)
            menu.addItem(color)
            add(String(localized: "Remove from Favorites"), #selector(removeFavorite), to: menu)
        case let .place(place) where place.kind == .disconnectedShare:
            add(String(localized: "Forget Share"), #selector(forgetShare), to: menu)
        case let .place(place) where !place.isRemote:
            add(String(localized: "Add to Favorites"), #selector(addPlaceToFavorites), to: menu)
            addCatalogItems(for: place, to: menu)
        case .place:
            break
        case .header, .tag:
            break
        }
    }

    func add(_ title: String, _ action: Selector, to menu: NSMenu) {
        menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
    }

    private func colorMenu(selected: Int) -> NSMenu {
        let menu = NSMenu()
        for (index, name) in Self.colorNames.enumerated() {
            let item = menu.addItem(withTitle: name, action: #selector(setFavoriteColor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = TagColors.dotImage(BranchPalette.color(at: index))
            item.state = index == selected ? .on : .off
        }
        return menu
    }

    // MARK: - Actions

    @objc func newWorkspace() {
        onCreateWorkspace?()
    }

    @objc private func renameWorkspace() {
        let row = outlineView.clickedRow
        guard case let .workspace(workspace) = node(at: row)?.kind,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let field = cell.textField else { return }
        renamingWorkspaceID = workspace.id
        field.isEditable = true
        view.window?.makeFirstResponder(field)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let id = renamingWorkspaceID else { return }
        renamingWorkspaceID = nil
        field.isEditable = false
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            try? database.renameWorkspace(id, to: name)
        }
        reload()
    }

    @objc private func deleteWorkspace() {
        guard case let .workspace(workspace) = node(at: outlineView.clickedRow)?.kind, let window = view.window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete the workspace “\(workspace.name)”?")
        alert.informativeText = String(localized: "Its canvas will be lost. Your files are not affected.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.onDeleteWorkspace?(workspace.id) }
        }
    }

    @objc private func setFavoriteColor(_ sender: NSMenuItem) {
        guard case let .favorite(favorite) = node(at: outlineView.clickedRow)?.kind else { return }
        try? database.setFavoriteColor(favorite.id, to: sender.tag)
        reload()
    }

    @objc private func removeFavorite() {
        guard case let .favorite(favorite) = node(at: outlineView.clickedRow)?.kind else { return }
        try? database.removeFavorite(favorite.id)
        reload()
    }

    @objc private func addPlaceToFavorites() {
        guard case let .place(place) = node(at: outlineView.clickedRow)?.kind else { return }
        addFavorites([place.url], at: nil)
    }

    /// Adds folders to the favorites, at `index` (or the end). Folders already there move.
    func addFavorites(_ urls: [URL], at index: Int?) {
        var position = index
        for url in urls {
            let favorite = (try? database.addFavorite(url, colorIndex: nil)) ?? nil
            let id = favorite?.id ?? ((try? database.favorites()) ?? []).first { $0.path == url.path }?.id
            if let id, let target = position {
                try? database.moveFavorite(id, to: target)
                position = target + 1
            }
        }
        reload()
    }
}
