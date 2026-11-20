import AppKit
import IndexKit

/// Loading a panel's folder, with folder sizes from the index.
extension FolderPanelController {
    /// Reads the folder in the background, keeping the selection by name.
    func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        let url = url
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try DirectoryReader.entries(at: url) }
            }.value
            guard generation == loadGeneration else { return }
            apply(result)
        }
    }

    func apply(_ result: Result<[DirectoryEntry], any Error>) {
        let selectedNames = Set(selectedItems.map(\.name))
        switch result {
        case let .success(entries):
            folderSizes = sizeLookup?(canonicalPath) ?? [:]
            items = entries.filter { !$0.isHidden }
                .map { FolderItem(entry: $0, in: url) }
                .sorted(by: sortKey, ascending: ascending, folderSizes: folderSizes)
            messageLabel.isHidden = true
        case let .failure(error):
            items = []
            messageLabel.stringValue = Self.message(for: error)
            messageLabel.isHidden = false
        }
        panelView.countLabel.stringValue = String(localized: "\(items.count) items")
        reloadViews(selecting: selectedNames)
    }

    static func message(for error: any Error) -> String {
        switch (error as? POSIXError)?.code {
        case .EPERM, .EACCES:
            String(localized: "Arbor can’t read this folder. Grant Full Disk Access in System Settings to see it.")
        case .ENOENT, .ENOTDIR:
            String(localized: "This folder no longer exists.")
        default:
            String(localized: "This folder can’t be read: \(error.localizedDescription)")
        }
    }

    func reloadViews(selecting names: Set<String>) {
        let indexes = IndexSet(items.indices.filter { names.contains(items[$0].name) })
        tableView.reloadData()
        collectionView.reloadData()
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        collectionView.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
        onSelectionChange?(selectedItems)
        onRowsMoved?()
    }

    func rowIndex(forName name: String) -> Int? {
        items.firstIndex { $0.name == name }
    }

    /// Selects exactly the items named in `names` (those present), reporting the change.
    func select(names: Set<String>) {
        let indexes = IndexSet(items.indices.filter { names.contains(items[$0].name) })
        switch mode {
        case .list:
            tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        case .icons:
            collectionView.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
            onSelectionChange?(selectedItems)
        }
    }

    /// Reloads folder sizes from the index (after it changed), keeping the selection.
    func refreshSizes() {
        let sizes = sizeLookup?(canonicalPath) ?? [:]
        guard sizes != folderSizes else { return }
        folderSizes = sizes
        if showsSizeBars {
            // Bar lengths depend on every size: redraw all rows.
            let selected = Set(selectedItems.map(\.name))
            if sortKey == .size {
                items = items.sorted(by: sortKey, ascending: ascending, folderSizes: folderSizes)
            }
            reloadViews(selecting: selected)
            return
        }
        if sortKey == .size {
            let selected = Set(selectedItems.map(\.name))
            items = items.sorted(by: sortKey, ascending: ascending, folderSizes: folderSizes)
            reloadViews(selecting: selected)
        } else {
            let column = tableView.column(withIdentifier: NSUserInterfaceItemIdentifier(FolderSortKey.size.rawValue))
            tableView.reloadData(forRowIndexes: IndexSet(items.indices), columnIndexes: IndexSet(integer: column))
        }
    }

    /// Deselects the item named `name`; the selection change closes its child panel.
    func deselect(_ name: String) {
        guard let index = items.firstIndex(where: { $0.name == name }) else { return }
        switch mode {
        case .list:
            tableView.deselectRow(index)
        case .icons:
            collectionView.deselectItems(at: [IndexPath(item: index, section: 0)])
            onSelectionChange?(selectedItems)
        }
    }
}
