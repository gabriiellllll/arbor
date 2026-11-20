import AppKit
import CanvasKit

/// A row of the sidebar outline. A class, because NSOutlineView tracks items by identity.
final class SidebarNode: NSObject {
    enum Kind {
        case header(Section)
        case workspace(Workspace)
        case favorite(Favorite)
        case place(Place)
    }

    enum Section {
        case workspaces, favorites, locations
    }

    let kind: Kind
    let children: [SidebarNode]

    init(_ kind: Kind, children: [SidebarNode] = []) {
        self.kind = kind
        self.children = children
    }
}

/// Sidebar: workspaces, favorites (each with its branch color) and locations.
@MainActor
final class SidebarViewController: NSViewController {
    /// Open a folder as a root panel, in the given color (favorites) or the least used one.
    var onOpen: ((URL, Int?) -> Void)?
    var onSwitchWorkspace: ((Int64) -> Void)?
    var onCreateWorkspace: (() -> Void)?
    var onDeleteWorkspace: ((Int64) -> Void)?

    let database: AppDatabase
    let outlineView = SidebarOutlineView()
    var sections: [SidebarNode] = []
    var currentWorkspaceID: Int64?
    /// The workspace whose name is being edited inline.
    var renamingWorkspaceID: Int64?

    init(database: AppDatabase) {
        self.database = database
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("sidebar"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(clicked)
        outlineView.menu = makeContextMenu()
        outlineView.onDelete = { [weak self] in self?.removeSelectedFavorite() }
        outlineView.setAccessibilityIdentifier("sidebar")
        setUpDragAndDrop()
        let scroll = NSScrollView()
        scroll.documentView = outlineView
        scroll.drawsBackground = false
        view = scroll

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspaceCenter.addObserver(self, selector: #selector(volumesChanged), name: name, object: nil)
        }
        reload()
    }

    /// Rebuilds the outline from the database and the current locations.
    func reload() {
        let workspaces = (try? database.workspaces()) ?? []
        let favorites = (try? database.favorites()) ?? []
        currentWorkspaceID = try? database.currentWorkspaceID()
        sections = [
            SidebarNode(.header(.workspaces), children: workspaces.map { SidebarNode(.workspace($0)) }),
            SidebarNode(.header(.favorites), children: favorites.map { SidebarNode(.favorite($0)) }),
            SidebarNode(.header(.locations), children: Locations.all().map { SidebarNode(.place($0)) }),
        ]
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    func node(at row: Int) -> SidebarNode? {
        row >= 0 ? outlineView.item(atRow: row) as? SidebarNode : nil
    }

    func section(_ section: SidebarNode.Section) -> SidebarNode? {
        sections.first {
            if case let .header(kind) = $0.kind {
                return kind == section
            }
            return false
        }
    }

    @objc private func clicked() {
        guard let node = node(at: outlineView.clickedRow) else { return }
        switch node.kind {
        case let .workspace(workspace):
            onSwitchWorkspace?(workspace.id)
        case let .favorite(favorite):
            onOpen?(favorite.url, favorite.colorIndex)
        case let .place(place):
            onOpen?(place.url, nil)
        case .header:
            break
        }
    }

    @objc private func volumesChanged() {
        reload()
    }

    private func removeSelectedFavorite() {
        guard case let .favorite(favorite) = node(at: outlineView.selectedRow)?.kind else { return }
        try? database.removeFavorite(favorite.id)
        reload()
    }
}

// MARK: - Outline

extension SidebarViewController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarNode)?.children.count ?? sections.count
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarNode)?.children[index] ?? sections[index]
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? SidebarNode)?.children.isEmpty ?? true)
    }

    func outlineView(_: NSOutlineView, isGroupItem item: Any) -> Bool {
        if case .header = (item as? SidebarNode)?.kind {
            return true
        }
        return false
    }

    func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        !outlineView(outlineView, isGroupItem: item)
    }

    func outlineView(_: NSOutlineView, viewFor _: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        switch node.kind {
        case let .header(section):
            return SidebarCell.header(Self.title(of: section))
        case let .workspace(workspace):
            let cell = SidebarCell.row(
                title: workspace.name,
                icon: NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: nil),
                dot: nil
            )
            cell.textField?.font = workspace.id == currentWorkspaceID
                ? .boldSystemFont(ofSize: NSFont.systemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
            cell.textField?.delegate = self
            return cell
        case let .favorite(favorite):
            return SidebarCell.row(
                title: FileManager.default.displayName(atPath: favorite.path),
                icon: NSWorkspace.shared.icon(forFile: favorite.path),
                dot: BranchPalette.color(at: favorite.colorIndex)
            )
        case let .place(place):
            return SidebarCell.row(title: place.name, icon: NSWorkspace.shared.icon(forFile: place.url.path), dot: nil)
        }
    }

    static func title(of section: SidebarNode.Section) -> String {
        switch section {
        case .workspaces: String(localized: "Workspaces")
        case .favorites: String(localized: "Favorites")
        case .locations: String(localized: "Locations")
        }
    }
}

/// Sidebar outline that reports the Delete key.
@MainActor
final class SidebarOutlineView: NSOutlineView {
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.specialKey == .delete || event.specialKey == .deleteForward {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// Sidebar cells.
@MainActor
enum SidebarCell {
    static func header(_ title: String) -> NSTableCellView {
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    static func row(title: String, icon: NSImage?, dot: NSColor?) -> NSTableCellView {
        let cell = NSTableCellView()
        let dotView = NSView()
        dotView.wantsLayer = true
        dotView.layer?.cornerRadius = 4
        dotView.layer?.backgroundColor = dot?.cgColor
        let image = NSImageView(image: icon ?? NSImage())
        let label = NSTextField(labelWithString: title)
        label.lineBreakMode = .byTruncatingTail
        for subview in [dotView, image, label] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(subview)
        }
        cell.imageView = image
        cell.textField = label
        NSLayoutConstraint.activate([
            dotView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            dotView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            dotView.widthAnchor.constraint(equalToConstant: 8),
            dotView.heightAnchor.constraint(equalToConstant: 8),
            image.leadingAnchor.constraint(equalTo: dotView.trailingAnchor, constant: 6),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }
}
