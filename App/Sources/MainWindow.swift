import AppKit

/// The main window. NSWindow answers Undo and Redo with its undo manager; file operations
/// keep their own history (they finish asynchronously), so Undo and Redo go to it unless the
/// user is editing text.
@MainActor
final class MainWindow: NSWindow {
    var fileUndoName: (() -> String?)?
    var fileRedoName: (() -> String?)?
    var onFileUndo: (() -> Void)?
    var onFileRedo: (() -> Void)?

    private var isEditingText: Bool {
        firstResponder is NSText
    }

    @objc func undo(_: Any?) {
        if isEditingText {
            undoManager?.undo()
        } else {
            onFileUndo?()
        }
    }

    @objc func redo(_: Any?) {
        if isEditingText {
            undoManager?.redo()
        } else {
            onFileRedo?()
        }
    }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard !isEditingText else { return super.validateMenuItem(item) }
        switch item.action {
        case #selector(undo(_:)):
            let name = fileUndoName?()
            item.title = name.map { String(localized: "Undo \($0)") } ?? String(localized: "Undo")
            return name != nil
        case #selector(redo(_:)):
            let name = fileRedoName?()
            item.title = name.map { String(localized: "Redo \($0)") } ?? String(localized: "Redo")
            return name != nil
        default:
            return super.validateMenuItem(item)
        }
    }
}
