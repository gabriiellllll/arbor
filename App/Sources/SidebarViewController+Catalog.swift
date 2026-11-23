import AppKit
import DiskKit
import SwiftUI

/// Sidebar disk commands: add a disk to the catalog (it stays browsable and searchable while
/// unplugged), remove it, and show its details.
extension SidebarViewController {
    func addCatalogItems(for place: Place, to menu: NSMenu) {
        guard let index, place.kind == .volume || place.kind == .offlineDisk || place.kind == .computer else { return }
        menu.addItem(.separator())
        if index.catalogRoot(at: place.url.path) == nil {
            add(String(localized: "Add to Catalog"), #selector(addToCatalog), to: menu)
        } else if place.kind != .computer {
            add(String(localized: "Remove from Catalog…"), #selector(removeFromCatalog), to: menu)
        }
        add(String(localized: "Disk Details…"), #selector(showDiskDetails), to: menu)
    }

    private var clickedPlace: Place? {
        if case let .place(place) = node(at: outlineView.clickedRow)?.kind {
            return place
        }
        return nil
    }

    @objc private func addToCatalog() {
        guard let place = clickedPlace else { return }
        index?.addToCatalog(place.url)
    }

    @objc private func removeFromCatalog() {
        guard let place = clickedPlace, let root = index?.catalogRoot(at: place.url.path), let window = view.window
        else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Remove “\(place.name)” from the catalog?")
        alert.informativeText = String(localized: """
        Its folders will no longer be browsable or searchable while it is unplugged. Files on the disk are \
        not affected.
        """)
        alert.addButton(withTitle: String(localized: "Remove"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            MainActor.assumeIsolated { self?.index?.removeRoot(root.id) }
        }
    }

    @objc private func showDiskDetails() {
        guard let place = clickedPlace else { return }
        let connected = place.kind != .offlineDisk
        guard let details = connected
            ? DiskDetails.of(volume: place.url) : index?.catalogRoot(at: place.url.path)?.diskDetails
        else {
            NSSound.beep()
            return
        }
        let host = NSHostingController(rootView: DiskDetailsView(details: details, isConnected: connected))
        host.rootView.onClose = { [weak host] in host?.dismiss(nil) }
        presentAsSheet(host)
    }
}

/// A disk's details: vendor, model, serial number, connection, capacity, file system.
struct DiskDetailsView: View {
    let details: DiskDetails
    let isConnected: Bool
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(details.name, systemImage: isConnected ? "externaldrive" : "externaldrive.badge.xmark")
                .font(.title2)
            if !isConnected {
                Text("Not plugged in. These details were saved when it was last connected.")
                    .foregroundStyle(.secondary)
            }
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                row("Vendor", details.vendor)
                row("Model", details.model)
                row("Serial Number", details.serialNumber)
                row(
                    "Connection",
                    details.connection.map { details.isInternal ? String(localized: "\($0) (internal)") : $0 }
                )
                row(
                    "Capacity",
                    details.capacity.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                )
                row("File System", details.fileSystem)
                row("Volume UUID", details.volumeUUID)
            }
            HStack {
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func row(_ label: LocalizedStringKey, _ value: String?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value ?? String(localized: "Unknown")).textSelection(.enabled)
        }
    }
}
