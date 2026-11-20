import FileOpsKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class InspectorModel {
    var item: FolderItem?
}

/// Right-hand inspector: details of the single selected item.
struct InspectorView: View {
    let model: InspectorModel

    var body: some View {
        if let item = model.item {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Image(nsImage: FileIcons.icon(for: item))
                        .resizable()
                        .frame(width: 64, height: 64)
                        .frame(maxWidth: .infinity)
                    Text(item.name)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Divider()
                    Grid(alignment: .leading, verticalSpacing: 6) {
                        row("Kind", kind(of: item))
                        if !item.isFolder {
                            row("Size", ByteCountFormatter.string(fromByteCount: item.entry.size, countStyle: .file))
                        }
                        row("Created", item.entry.created.formatted(date: .abbreviated, time: .shortened))
                        row("Modified", item.entry.modified.formatted(date: .abbreviated, time: .shortened))
                        row("Where", item.url.deletingLastPathComponent().path)
                        let tags = (try? FinderTags.tags(of: item.url)) ?? []
                        if !tags.isEmpty {
                            row("Tags", tags.joined(separator: ", "))
                        }
                    }
                    .font(.callout)
                }
                .padding()
            }
        } else {
            Text("No Selection")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }

    private func kind(of item: FolderItem) -> String {
        if item.isFolder {
            return UTType.folder.localizedDescription ?? ""
        }
        let type = UTType(filenameExtension: (item.name as NSString).pathExtension) ?? .data
        return type.localizedDescription ?? ""
    }
}
