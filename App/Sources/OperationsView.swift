import FileOpsKit
import Observation
import SwiftUI

/// The operations list shown in the toolbar popover.
@MainActor
@Observable
final class OperationsModel {
    struct Row: Identifiable, Equatable {
        let id: UUID
        let title: String
        let state: FileOperationQueue.State
        let progress: OperationProgress

        init(item: FileOperationQueue.Item) {
            id = item.id
            title = FileOperationsController.title(for: item.operation)
            state = item.state
            progress = item.progress
        }
    }

    var rows: [Row] = []
}

struct OperationsView: View {
    let model: OperationsModel
    let queue: FileOperationQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("File Operations").font(.headline)
                Spacer()
                Button("Clear") { queue.clearDone() }
                    .disabled(!model.rows.contains {
                        if case .done = $0.state {
                            true
                        } else {
                            false
                        }
                    })
            }
            if model.rows.isEmpty {
                Text("No operations").foregroundStyle(.secondary)
            }
            ForEach(model.rows) { row in
                OperationRow(row: row, queue: queue)
            }
        }
        .padding()
        .frame(width: 360)
    }
}

private struct OperationRow: View {
    let row: OperationsModel.Row
    let queue: FileOperationQueue

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.title).lineLimit(1).truncationMode(.middle)
                Spacer()
                controls
            }
            switch row.state {
            case .queued:
                Text("Waiting").font(.caption).foregroundStyle(.secondary)
            case .running, .paused:
                ProgressView(value: row.progress.fraction)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            case let .done(result):
                Text(outcome(result.outcome)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var controls: some View {
        switch row.state {
        case .running, .queued:
            Button { queue.pause(row.id) } label: { Image(systemName: "pause.fill") }
                .buttonStyle(.borderless).help(Text("Pause"))
            Button { queue.cancel(row.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).help(Text("Cancel"))
        case .paused:
            Button { queue.resume(row.id) } label: { Image(systemName: "play.fill") }
                .buttonStyle(.borderless).help(Text("Resume"))
            Button { queue.cancel(row.id) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).help(Text("Cancel"))
        case .done:
            EmptyView()
        }
    }

    private var detail: String {
        let progress = row.progress
        if row.state == .paused {
            return String(localized: "Paused")
        }
        if progress.totalBytes > 0 {
            let done = ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
            return String(localized: "\(done) of \(total)")
        }
        return String(localized: "\(progress.completedItems) of \(progress.totalItems) items")
    }

    private func outcome(_ outcome: OperationOutcome) -> String {
        switch outcome {
        case .finished: String(localized: "Done")
        case .stopped: String(localized: "Stopped")
        case .cancelled: String(localized: "Cancelled")
        case let .failed(message): String(localized: "Failed: \(message)")
        }
    }
}
