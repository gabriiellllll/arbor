import AppKit
import FileOpsKit

/// Runs the user's file operations: queue, conflict sheets, failure alerts, undo and redo.
@MainActor
final class FileOperationsController {
    let queue: FileOperationQueue
    let model = OperationsModel()
    weak var window: NSWindow?
    /// Called when the queue starts or stops having work.
    var onBusyChange: ((Bool) -> Void)?

    private(set) var history = UndoHistory()

    private enum Origin {
        case user, undo, redo
    }

    private var pending: [UUID: (name: String, origin: Origin)] = [:]
    private var wasBusy = false

    init(runner: FileOperationRunner) {
        queue = FileOperationQueue(runner: runner)
        queue.onChange = { [weak self] in self?.queueChanged() }
        queue.onFinish = { [weak self] operation, result in self?.finished(operation, result) }
        queue.resolveConflict = { [weak self] conflict in
            await self?.askConflict(conflict) ?? ConflictAnswer(decision: .stop, applyToAll: false)
        }
    }

    /// Queues a user action; `name` titles its Undo menu item ("Copy", "Move to Trash"…).
    func perform(_ operation: FileOperation, name: String) {
        pending[operation.id] = (name, .user)
        queue.enqueue(operation)
    }

    func undo() {
        guard let name = history.undoName, let revert = history.undo() else { return }
        pending[revert.id] = (name, .undo)
        queue.enqueue(revert)
    }

    func redo() {
        guard let redo = history.redo() else { return }
        pending[redo.operation.id] = (redo.name, .redo)
        queue.enqueue(redo.operation)
    }

    private func finished(_ operation: FileOperation, _ result: OperationResult) {
        let info = pending.removeValue(forKey: operation.id)
        switch info?.origin {
        case .user: history.record(operation, result: result, name: info?.name ?? "")
        case .redo: history.recordRedone(operation, result: result, name: info?.name ?? "")
        case .undo, nil: break
        }
        if case let .failed(message) = result.outcome {
            let alert = NSAlert()
            alert.messageText = String(localized: "The operation couldn’t be completed.")
            alert.informativeText = message
            if let window {
                alert.beginSheetModal(for: window)
            } else {
                alert.runModal()
            }
        }
    }

    private func queueChanged() {
        model.rows = queue.items.map { OperationsModel.Row(item: $0) }
        let busy = queue.isBusy
        if busy != wasBusy {
            wasBusy = busy
            onBusyChange?(busy)
        }
    }

    // MARK: - Conflicts

    private func askConflict(_ conflict: Conflict) async -> ConflictAnswer {
        let alert = NSAlert()
        let folder = conflict.existing.deletingLastPathComponent().lastPathComponent
        alert.messageText = String(
            localized: "An item named “\(conflict.existing.lastPathComponent)” already exists in “\(folder)”."
        )
        alert.informativeText = String(localized: "Replacing moves the existing item to the Trash.")
        let decisions: [(String, ConflictDecision)] = [
            (String(localized: "Replace"), .replace),
            (String(localized: "Keep Both"), .keepBoth),
            (String(localized: "Skip"), .skip),
            (String(localized: "Stop"), .stop),
        ]
        for (title, _) in decisions {
            alert.addButton(withTitle: title)
        }
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Apply to All")
        let response: NSApplication.ModalResponse = if let window {
            await alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let decision = decisions.indices.contains(index) ? decisions[index].1 : .stop
        return ConflictAnswer(decision: decision, applyToAll: alert.suppressionButton?.state == .on)
    }

    // MARK: - Titles

    /// What the operations list shows for an operation.
    nonisolated static func title(for operation: FileOperation) -> String {
        let count = operation.sources.count
        let first = operation.sources.first?.lastPathComponent ?? ""
        switch operation.kind {
        case let .copy(folder):
            return count == 1
                ? String(localized: "Copying “\(first)” to “\(folder.lastPathComponent)”")
                : String(localized: "Copying \(count) items to “\(folder.lastPathComponent)”")
        case let .move(folder):
            return count == 1
                ? String(localized: "Moving “\(first)” to “\(folder.lastPathComponent)”")
                : String(localized: "Moving \(count) items to “\(folder.lastPathComponent)”")
        case .trash:
            return count == 1
                ? String(localized: "Moving “\(first)” to the Trash")
                : String(localized: "Moving \(count) items to the Trash")
        case let .rename(name):
            return String(localized: "Renaming “\(first)” to “\(name)”")
        case .renameAll:
            return String(localized: "Renaming \(count) items")
        case .revert:
            return String(localized: "Undoing")
        }
    }
}
