import AppKit
import CanvasKit

/// Sidebar. Lists standard places, each with a branch color; clicking one opens it as a root
/// panel in that color.
@MainActor
final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onOpen: ((URL, Int) -> Void)?

    private let places: [URL] = {
        let manager = FileManager.default
        let userFolders = [.desktopDirectory, .documentDirectory, .downloadsDirectory]
            .compactMap { manager.urls(for: $0, in: .userDomainMask).first }
        return [manager.homeDirectoryForCurrentUser] + userFolders + [URL(fileURLWithPath: "/Applications")]
    }()

    private let tableView = NSTableView()

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("place"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(clicked)
        tableView.setAccessibilityIdentifier("sidebar")
        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.drawsBackground = false
        view = scroll
    }

    func numberOfRows(in _: NSTableView) -> Int {
        places.count
    }

    func tableView(_: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        let url = places[row]
        let cell = NSTableCellView()
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = BranchPalette.color(at: row).cgColor
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        let label = NSTextField(labelWithString: FileManager.default.displayName(atPath: url.path))
        label.lineBreakMode = .byTruncatingTail
        for subview in [dot, icon, label] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(subview)
        }
        cell.imageView = icon
        cell.textField = label
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            dot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 8),
            dot.heightAnchor.constraint(equalToConstant: 8),
            icon.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func clicked() {
        guard places.indices.contains(tableView.clickedRow) else { return }
        onOpen?(places[tableView.clickedRow], tableView.clickedRow)
    }
}
