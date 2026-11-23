import AppKit
import DiskKit
import IndexKit
import Observation
import SwiftUI

/// What the Index settings show: indexed volumes, roots with their exclusions, scan status.
@MainActor
@Observable
final class IndexSettingsModel {
    struct VolumeRow: Identifiable {
        let path: String
        let name: String
        let rootID: Int64?

        var id: String {
            path
        }
    }

    struct RootRow: Identifiable {
        let root: IndexRoot
        let items: Int64
        let totalSize: Int64

        var id: Int64 {
            root.id
        }
    }

    private let index: IndexService
    private(set) var volumes: [VolumeRow] = []
    private(set) var roots: [RootRow] = []
    private(set) var status: IndexCoordinator.Status = .idle

    init(index: IndexService) {
        self.index = index
        refresh()
    }

    func refresh() {
        let roots = index.roots()
        self.roots = roots.map { root in
            let summary = index.summary(of: root)
            return RootRow(root: root, items: summary.items, totalSize: summary.totalSize)
        }
        volumes = MountedVolumes.current().map { volume in
            let path = volume.url.path
            return VolumeRow(path: path, name: volume.name, rootID: roots.first { $0.path == path }?.id)
        } + index.offlineDisks().map { root in
            VolumeRow(path: root.path, name: String(localized: "\(root.diskName) (not plugged in)"), rootID: root.id)
        }
        status = index.status
    }

    func setIndexed(_ volume: VolumeRow, _ indexed: Bool) {
        if indexed, volume.rootID == nil {
            index.addRoot(path: volume.path, exclusions: volume.path == "/" ? IndexService.defaultExclusions : [])
        } else if !indexed, let id = volume.rootID {
            index.removeRoot(id)
        }
    }

    func addExclusion(_ path: String, to row: RootRow) {
        guard !row.root.exclusions.contains(path) else { return }
        index.setExclusions(row.root.id, row.root.exclusions + [path])
    }

    func removeExclusion(_ path: String, from row: RootRow) {
        index.setExclusions(row.root.id, row.root.exclusions.filter { $0 != path })
    }

    func rebuild(_ row: RootRow) {
        index.rebuild(row.root.id)
    }
}

/// Settings › Index. What is indexed comes first; every mounted volume is listed after.
struct IndexSettingsView: View {
    let model: IndexSettingsModel

    var body: some View {
        Form {
            Section {
                statusLine
            }
            ForEach(model.roots) { row in
                Section(row.root.path) {
                    LabeledContent("Indexed", value: summary(row))
                        .accessibilityIdentifier("indexedRoot")
                    ForEach(row.root.exclusions, id: \.self) { path in
                        HStack {
                            Text(path).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button(role: .destructive) { model.removeExclusion(path, from: row) } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help(Text("Remove Exclusion"))
                        }
                    }
                    HStack {
                        Button("Add Exclusion…") { chooseExclusion(for: row) }
                        Spacer()
                        Button("Rebuild") { model.rebuild(row) }
                    }
                }
            }
            Section {
                ForEach(model.volumes) { volume in
                    Toggle(isOn: Binding(
                        get: { volume.rootID != nil },
                        set: { model.setIndexed(volume, $0) }
                    )) {
                        Text(volume.name)
                    }
                }
            } header: {
                Text("Indexed Volumes")
            } footer: {
                Text("Indexed disks stay in the catalog: browsable and searchable while unplugged.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
    }

    @ViewBuilder private var statusLine: some View {
        switch model.status {
        case .idle:
            Label("Index up to date", systemImage: "checkmark.circle")
        case let .scanning(path, items):
            HStack {
                ProgressView().controlSize(.small)
                Text("Scanning “\(path)”: \(items.formatted()) items")
            }
        case let .readingTags(path):
            HStack {
                ProgressView().controlSize(.small)
                Text("Reading Finder tags in “\(path)”")
            }
        }
    }

    private func summary(_ row: IndexSettingsModel.RootRow) -> String {
        let size = ByteCountFormatter.string(fromByteCount: row.totalSize, countStyle: .file)
        guard let scanned = row.root.scannedAt else {
            return String(localized: "Not scanned yet")
        }
        let when = scanned.formatted(.relative(presentation: .named))
        return String(localized: "\(row.items.formatted()) items, \(size), scanned \(when)")
    }

    private func chooseExclusion(for row: IndexSettingsModel.RootRow) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = URL(fileURLWithPath: row.root.path, isDirectory: true)
        panel.prompt = String(localized: "Exclude")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.addExclusion(FolderWatcher.canonicalPath(of: url), to: row)
    }
}

/// The Settings window.
@MainActor
final class SettingsWindowController: NSWindowController {
    let model: IndexSettingsModel

    init(index: IndexService) {
        model = IndexSettingsModel(index: index)
        let window = NSWindow(contentViewController: NSHostingController(rootView: IndexSettingsView(model: model)))
        window.title = String(localized: "Settings")
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.styleMask = [.titled, .closable]
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var isVisible: Bool {
        window?.isVisible == true
    }
}
