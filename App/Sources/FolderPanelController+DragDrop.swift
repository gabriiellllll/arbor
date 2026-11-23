import AppKit

/// Dropping files on a panel moves them into its folder, or into the folder row under the
/// pointer (⌥ copies). Return renames the selected item in place.
extension FolderPanelController: NSTextFieldDelegate {
    func setUpDragAndDrop() {
        for view in [tableView, collectionView] as [NSView] {
            view.registerForDraggedTypes([.fileURL])
        }
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        tableView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        collectionView.setDraggingSourceOperationMask([.copy, .move], forLocal: false)
        tableView.onReturn = { [weak self] in self?.beginRename() }
    }

    /// Rows can be dragged out: to other panels, the sidebar favorites, or Finder.
    func tableView(_: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        items.indices.contains(row) ? items[row].url as NSURL : nil
    }

    func collectionView(_: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        items.indices.contains(indexPath.item) ? items[indexPath.item].url as NSURL : nil
    }

    func droppedURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
            ?? []
    }

    /// Move unless the source only allows copying (⌥ held, or another volume in Finder).
    func dropOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        info.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    /// Where a drop on `row` goes: that folder row, or this panel's folder.
    func dropDestination(row: Int, onItem: Bool) -> URL {
        onItem && items.indices.contains(row) && items[row].isFolder ? items[row].url : url
    }

    /// Refused when an item is the destination or contains it (it can't go into itself), and
    /// when every item already is in the destination.
    func isUsefulDrop(_ urls: [URL], into destination: URL) -> Bool {
        let target = destination.standardizedFileURL.path
        let paths = urls.map(\.standardizedFileURL.path)
        if paths.contains(where: { target == $0 || target.hasPrefix($0 + "/") }) {
            return false
        }
        return urls.contains { $0.deletingLastPathComponent().standardizedFileURL.path != target }
    }

    func tableView(
        _ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
        proposedDropOperation operation: NSTableView.DropOperation
    ) -> NSDragOperation {
        let onFolder = operation == .on && items.indices.contains(row) && items[row].isFolder
        if !onFolder {
            tableView.setDropRow(-1, dropOperation: .on)
        }
        let urls = droppedURLs(info)
        let destination = dropDestination(row: row, onItem: onFolder)
        return offlineDisk == nil && !urls.isEmpty && isUsefulDrop(urls, into: destination) ? dropOperation(info) : []
    }

    func tableView(
        _: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation operation: NSTableView.DropOperation
    ) -> Bool {
        let urls = droppedURLs(info)
        guard !urls.isEmpty else { return false }
        let destination = dropDestination(row: row, onItem: operation == .on)
        onDropFiles?(urls, destination, dropOperation(info) == .copy)
        return true
    }

    func collectionView(
        _: NSCollectionView, validateDrop info: NSDraggingInfo,
        proposedIndexPath indexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>,
        dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>
    ) -> NSDragOperation {
        let row = indexPath.pointee.item
        let onFolder = dropOperation.pointee == .on && items.indices.contains(row) && items[row].isFolder
        let urls = droppedURLs(info)
        return offlineDisk == nil && !urls.isEmpty && isUsefulDrop(
            urls,
            into: dropDestination(row: row, onItem: onFolder)
        )
            ? self.dropOperation(info) : []
    }

    func collectionView(
        _: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath,
        dropOperation: NSCollectionView.DropOperation
    ) -> Bool {
        let urls = droppedURLs(info)
        guard !urls.isEmpty else { return false }
        onDropFiles?(
            urls,
            dropDestination(row: indexPath.item, onItem: dropOperation == .on),
            self.dropOperation(info) == .copy
        )
        return true
    }

    // MARK: - Rename in place

    /// Edits the name of the single selected item (list mode).
    func beginRename() {
        guard mode == .list, offlineDisk == nil, selectedIndexes.count == 1, let row = selectedIndexes.first,
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NSTableCellView,
              let field = cell.textField else { return }
        renamingItem = items[row]
        field.isEditable = true
        field.delegate = self
        tableView.window?.makeFirstResponder(field)
        // Select the name without its extension, like Finder.
        let name = items[row].name as NSString
        let stem = items[row].isFolder || name.pathExtension.isEmpty ? name.length : name.length - name.pathExtension
            .count - 1
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: stem)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let item = renamingItem else { return }
        renamingItem = nil
        field.isEditable = false
        let name = field.stringValue
        if name != item.name, !name.isEmpty {
            onRename?(item.url, name)
        } else {
            field.stringValue = item.name
        }
    }
}

/// The list view of a panel; reports Return so the selected item can be renamed.
@MainActor
final class PanelTableView: NSTableView {
    var onReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.specialKey == .carriageReturn || event.specialKey == .enter {
            onReturn?()
        } else {
            super.keyDown(with: event)
        }
    }
}
