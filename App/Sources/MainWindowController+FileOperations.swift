import AppKit
import FileOpsKit
import SwiftUI

/// File commands (copy, paste, move here, trash, rename, undo, redo) and the operations
/// popover.
extension MainWindowController {
    func setUpFileOperations(in window: MainWindow) {
        operations.window = window
        canvas.onPerform = { [weak self] operation, name in self?.operations.perform(operation, name: name) }
        window.fileUndoName = { [weak self] in self?.operations.history.undoName }
        window.fileRedoName = { [weak self] in self?.operations.history.redoName }
        window.onFileUndo = { [weak self] in self?.operations.undo() }
        window.onFileRedo = { [weak self] in self?.operations.redo() }
        operations.onBusyChange = { [weak self] busy in self?.operationsBusyChanged(busy) }
        operationsPopover.behavior = .transient
        operationsPopover.contentViewController = NSHostingController(
            rootView: OperationsView(model: operations.model, queue: operations.queue)
        )
    }

    @objc func copy(_: Any?) {
        canvas.copySelectionToPasteboard()
    }

    @objc func paste(_: Any?) {
        canvas.pasteFiles(moving: false)
    }

    @objc func moveItemHere(_: Any?) {
        canvas.pasteFiles(moving: true)
    }

    @objc func moveToTrash(_: Any?) {
        canvas.trashSelection()
    }

    @objc func renameItem(_: Any?) {
        canvas.renameSelection()
    }

    @objc func showOperations(_: Any?) {
        if operationsPopover.isShown {
            operationsPopover.close()
        } else {
            operationsPopover.show(relativeTo: operationsButton.bounds, of: operationsButton, preferredEdge: .minY)
        }
    }

    func validateFileCommand(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(moveToTrash(_:)):
            !canvas.operationTargets.isEmpty
        case #selector(paste(_:)), #selector(moveItemHere(_:)):
            canvas.activeFolder != nil && NSPasteboard.general.canReadObject(
                forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]
            )
        case #selector(renameItem(_:)):
            canvas.activePanel.flatMap { canvas.panels[$0] }?.selectedItems.count == 1
        default:
            true
        }
    }

    /// Shows activity, and opens the operations list when work takes more than a second.
    private func operationsBusyChanged(_ busy: Bool) {
        operationsButton.contentTintColor = busy ? .controlAccentColor : nil
        guard busy else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, operations.queue.isBusy, !operationsPopover.isShown, operationsButton.window != nil else {
                return
            }
            showOperations(nil)
        }
    }

    func operationsItem() -> NSToolbarItem {
        let label = String(localized: "Operations")
        operationsButton.bezelStyle = .toolbar
        operationsButton.image = NSImage(
            systemSymbolName: "arrow.up.arrow.down.circle",
            accessibilityDescription: label
        )
        operationsButton.target = self
        operationsButton.action = #selector(showOperations(_:))
        operationsButton.setAccessibilityIdentifier("operations")
        let item = NSToolbarItem(itemIdentifier: Item.operations)
        item.label = label
        item.toolTip = label
        item.view = operationsButton
        return item
    }
}
