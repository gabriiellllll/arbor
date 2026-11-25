import AppKit
import DiskKit

/// The sidebar's Shared section: mounted network shares, remembered ones (reconnected in one
/// click) and SMB servers on the local network. macOS handles sign-in and the Keychain.
extension SidebarViewController {
    /// Starts listing the servers on the local network.
    func browseServers() {
        let browser = ServerBrowser()
        servers = browser
        browser.start()
    }

    /// The Shared section's places. Every mounted share is remembered, to reconnect it later.
    func sharedPlaces() -> [Place] {
        let mounted = MountedVolumes.current().filter(\.isNetwork)
        for volume in mounted {
            if let url = volume.remountURL {
                try? database.rememberShare(url, name: volume.name)
            }
        }
        return Locations.shared(
            mounted: mounted, remembered: (try? database.shares()) ?? [], servers: servers?.servers ?? []
        )
    }

    func remoteCell(_ place: Place) -> NSTableCellView {
        let symbol = place.kind == .server ? "server.rack" : "externaldrive.connected.to.line.below"
        let cell = SidebarCell.row(
            title: place.name, icon: NSImage(systemSymbolName: symbol, accessibilityDescription: nil), dot: nil
        )
        if place.kind == .disconnectedShare {
            cell.textField?.textColor = .secondaryLabelColor
            cell.toolTip = String(localized: "Not connected. Click to connect to \(place.url.host ?? place.name).")
        }
        return cell
    }

    /// Mounts a share or server (macOS asks for the password, or a share, if needed) and
    /// opens what was mounted.
    func connect(to url: URL, name: String) {
        Task { [weak self] in
            do {
                if let mountpoint = try await NetworkShares.mount(url).first {
                    self?.onOpen?(mountpoint, nil)
                }
            } catch {
                guard !NetworkShares.isCancellation(error), let window = self?.view.window else { return }
                let alert = NSAlert()
                alert.messageText = String(localized: "Couldn’t connect to “\(name)”.")
                alert.informativeText = error.localizedDescription
                alert.beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    /// Asks for a server address (`nas.local/Media`, `smb://…`, `nfs://…`) and connects to it.
    func askForServer() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Connect to Server")
        alert.informativeText = String(localized: "Enter a server address, such as smb://nas.local/Media.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 22))
        field.placeholderString = "smb://"
        field.setAccessibilityIdentifier("serverAddress")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Connect"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .alertFirstButtonReturn else { return }
                guard let url = NetworkShares.url(from: field.stringValue) else {
                    NSSound.beep()
                    return
                }
                self?.connect(to: url, name: url.host ?? field.stringValue)
            }
        }
    }

    @objc func forgetShare() {
        guard case let .place(place) = node(at: outlineView.clickedRow)?.kind else { return }
        try? database.forgetShare(place.url)
        reload()
    }
}
