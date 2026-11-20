import AppKit

/// Favorites drag and drop: reorder favorites, and drop folders (from panels or Finder) to
/// add them at the drop position.
extension SidebarViewController {
    static let favoriteType = NSPasteboard.PasteboardType("app.arbor.favorite")

    func setUpDragAndDrop() {
        outlineView.registerForDraggedTypes([.fileURL, Self.favoriteType])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
    }

    func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard case let .favorite(favorite) = (item as? SidebarNode)?.kind else { return nil }
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString("\(favorite.id)", forType: Self.favoriteType)
        pasteboardItem.setString(favorite.url.absoluteString, forType: .fileURL)
        return pasteboardItem
    }

    func outlineView(
        _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
        proposedChildIndex index: Int
    ) -> NSDragOperation {
        guard let favorites = section(.favorites) else { return [] }
        let reordering = info.draggingPasteboard.availableType(from: [Self.favoriteType]) != nil
        guard reordering || !folderURLs(in: info).isEmpty else { return [] }
        // Every drop lands in the favorites list: before a hovered favorite, or at the end.
        var target = favorites.children.count
        if let node = item as? SidebarNode {
            if node === favorites, index >= 0 {
                target = index
            } else if let hovered = favorites.children.firstIndex(of: node) {
                target = hovered
            }
        }
        outlineView.setDropItem(favorites, dropChildIndex: target)
        return reordering ? .move : .copy
    }

    func outlineView(_: NSOutlineView, acceptDrop info: NSDraggingInfo, item _: Any?, childIndex index: Int) -> Bool {
        if let value = info.draggingPasteboard.string(forType: Self.favoriteType), let id = Int64(value) {
            let current = section(.favorites)?.children.firstIndex {
                if case let .favorite(favorite) = $0.kind {
                    return favorite.id == id
                }
                return false
            } ?? index
            // Removing the dragged row first shifts later positions up by one.
            try? database.moveFavorite(id, to: current < index ? index - 1 : index)
            reload()
            return true
        }
        let urls = folderURLs(in: info)
        guard !urls.isEmpty else { return false }
        addFavorites(urls, at: index)
        return true
    }

    private func folderURLs(in info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(
            forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }
}
