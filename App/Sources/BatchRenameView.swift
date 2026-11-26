import AppKit
import FileOpsKit
import SwiftUI

extension CanvasViewController {
    /// Renames several selected items (across panels) with a sheet and live preview; one item
    /// is renamed in place.
    func renameSelection() {
        let targets = operationTargets
        guard targets.count > 1 else {
            activePanel.flatMap { panels[$0] }?.beginRename()
            return
        }
        // ponytail: dates (EXIF included) are read on the main thread when the sheet opens;
        // read them in the background if large photo batches feel slow.
        let subjects = targets.sorted { lhs, rhs in
            let left = lhs.deletingLastPathComponent().path, right = rhs.deletingLastPathComponent().path
            return left != right ? left < right
                : lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
        }.map(RenameSubject.load)
        let host = NSHostingController(rootView: BatchRenameView(subjects: subjects))
        host.rootView.onClose = { [weak host, weak self] rows in
            host?.dismiss(nil)
            let renamed = rows.filter(\.changes)
            guard !renamed.isEmpty else { return }
            self?.onPerform?(
                FileOperation(kind: .renameAll(newNames: renamed.map(\.newName)), sources: renamed.map(\.source)),
                String(localized: "Rename")
            )
        }
        presentAsSheet(host)
    }
}

/// Batch rename: find/replace, a name template with tokens, a case change, and a preview of
/// every new name. Renaming is blocked while a name is invalid or collides.
struct BatchRenameView: View {
    let subjects: [RenameSubject]
    /// The rows to rename, or none when cancelled.
    var onClose: ([RenamePreview.Row]) -> Void = { _ in }
    @State private var rules = RenameRules()

    private var preview: RenamePreview {
        BatchRename.preview(subjects, rules: rules)
    }

    var body: some View {
        let preview = preview
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(subjects.count) Items").font(.title2)
            Form {
                TextField("Find", text: $rules.find)
                TextField("Replace with", text: $rules.replace)
                HStack {
                    Toggle("Regular expression", isOn: $rules.usesRegex)
                    Toggle("Match case", isOn: $rules.caseSensitive)
                }
                HStack {
                    TextField("Name", text: $rules.template).accessibilityIdentifier("renameTemplate")
                    Menu("Insert") {
                        tokenButton("Name", "{name}")
                        tokenButton("Number", "{n:2}")
                        tokenButton("Date Created", "{created:yyyy-MM-dd}")
                        tokenButton("Date Modified", "{modified:yyyy-MM-dd}")
                        tokenButton("Photo Date", "{exif:yyyy-MM-dd}")
                    }
                    .fixedSize()
                }
                Stepper(value: $rules.startNumber, in: 0 ... 1_000_000) {
                    Text("Numbers start at \(rules.startNumber)")
                }
                Picker("Case", selection: $rules.caseChange) {
                    Text("Unchanged").tag(RenameRules.CaseChange.none)
                    Text("lowercase").tag(RenameRules.CaseChange.lower)
                    Text("UPPERCASE").tag(RenameRules.CaseChange.upper)
                    Text("Title Case").tag(RenameRules.CaseChange.title)
                }
                Toggle("Include the extension", isOn: $rules.includesExtension)
            }
            if let error = preview.patternError {
                Text(error).foregroundStyle(.red)
            }
            List(Array(preview.rows.enumerated()), id: \.offset) { _, row in
                PreviewRow(row: row)
            }
            .frame(minHeight: 220)
            .accessibilityIdentifier("renamePreview")
            HStack {
                Spacer()
                Button("Cancel") { onClose([]) }.keyboardShortcut(.cancelAction)
                Button("Rename") { onClose(preview.rows) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!preview.canRename)
            }
        }
        .padding(20)
        .frame(width: 620, height: 620)
    }

    private func tokenButton(_ title: LocalizedStringKey, _ token: String) -> some View {
        Button(title) { rules.template += token }
    }
}

/// One item of the preview: its name, its new name, and what is wrong with it.
private struct PreviewRow: View {
    let row: RenamePreview.Row

    var body: some View {
        HStack {
            Text(row.source.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary)
            Text(row.newName).lineLimit(1)
            Spacer()
            if let problem = row.problem {
                Text(Self.text(problem)).foregroundStyle(.red)
            }
        }
        .help(row.source.deletingLastPathComponent().path)
    }

    static func text(_ problem: RenamePreview.Problem) -> String {
        switch problem {
        case .invalidName: String(localized: "Invalid name")
        case .duplicate: String(localized: "Same name as another item")
        case .taken: String(localized: "Name already used in this folder")
        case .noPhotoDate: String(localized: "No photo date")
        }
    }
}
