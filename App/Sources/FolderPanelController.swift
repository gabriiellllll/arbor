import AppKit
import IndexKit

/// One folder panel: loads the folder, shows it as a sortable list or as icons, and reports
/// selection so the canvas can open child panels for selected folders.
@MainActor
final class FolderPanelController: NSObject {
    enum Mode: Int {
        case list, icons
    }

    let url: URL
    /// Path as FSEvents reports it, to match change notifications.
    let canonicalPath: String
    let panelView: PanelView

    private(set) var items: [FolderItem] = []

    /// Selected items changed (by the user or after a reload).
    var onSelectionChange: (([FolderItem]) -> Void)?
    /// Rows moved inside the panel (scroll, sort, reload, mode): branches must follow.
    var onRowsMoved: (() -> Void)?
    var onClose: (() -> Void)?

    private var mode: Mode = .list
    private var sortKey: FolderSortKey = .name
    private var ascending = true
    private var loadGeneration = 0

    private let tableView = NSTableView()
    private let tableScroll = NSScrollView()
    private let collectionView = NSCollectionView()
    private let collectionScroll = NSScrollView()
    private let messageLabel = NSTextField(wrappingLabelWithString: "")

    init(url: URL, frame: CGRect) {
        self.url = url
        canonicalPath = FolderWatcher.canonicalPath(of: url)
        panelView = PanelView(frame: frame)
        super.init()
        let name = FileManager.default.displayName(atPath: url.path)
        panelView.titleLabel.stringValue = name
        panelView.iconView.image = NSWorkspace.shared.icon(forFile: url.path)
        panelView.setAccessibilityElement(true)
        panelView.setAccessibilityRole(.group)
        panelView.setAccessibilityLabel(name)
        panelView.setAccessibilityIdentifier("panel.\(name)")
        panelView.modeControl.target = self
        panelView.modeControl.action = #selector(modeChanged)
        panelView.closeButton.target = self
        panelView.closeButton.action = #selector(close)
        setUpTable(name: name)
        setUpCollection()
        setUpMessage()
        show(.list)
    }

    var selectedItems: [FolderItem] {
        selectedIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    private var selectedIndexes: IndexSet {
        switch mode {
        case .list: tableView.selectedRowIndexes
        case .icons: IndexSet(collectionView.selectionIndexPaths.map(\.item))
        }
    }

    // MARK: - Loading

    /// Reads the folder in the background, keeping the selection by name.
    func reload() {
        loadGeneration += 1
        let generation = loadGeneration
        let url = url
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try DirectoryReader.entries(at: url) }
            }.value
            guard generation == loadGeneration else { return }
            apply(result)
        }
    }

    private func apply(_ result: Result<[DirectoryEntry], any Error>) {
        let selectedNames = Set(selectedItems.map(\.name))
        switch result {
        case let .success(entries):
            items = entries.filter { !$0.isHidden }
                .map { FolderItem(entry: $0, in: url) }
                .sorted(by: sortKey, ascending: ascending)
            messageLabel.isHidden = true
        case let .failure(error):
            items = []
            messageLabel.stringValue = Self.message(for: error)
            messageLabel.isHidden = false
        }
        panelView.countLabel.stringValue = String(localized: "\(items.count) items")
        reloadViews(selecting: selectedNames)
    }

    private static func message(for error: any Error) -> String {
        switch (error as? POSIXError)?.code {
        case .EPERM, .EACCES:
            String(localized: "Arbor can’t read this folder. Grant Full Disk Access in System Settings to see it.")
        case .ENOENT, .ENOTDIR:
            String(localized: "This folder no longer exists.")
        default:
            String(localized: "This folder can’t be read: \(error.localizedDescription)")
        }
    }

    private func reloadViews(selecting names: Set<String>) {
        let indexes = IndexSet(items.indices.filter { names.contains(items[$0].name) })
        tableView.reloadData()
        collectionView.reloadData()
        tableView.selectRowIndexes(indexes, byExtendingSelection: false)
        collectionView.selectionIndexPaths = Set(indexes.map { IndexPath(item: $0, section: 0) })
        onSelectionChange?(selectedItems)
        onRowsMoved?()
    }

    /// Deselects the item named `name`; the selection change closes its child panel.
    func deselect(_ name: String) {
        guard let index = items.firstIndex(where: { $0.name == name }) else { return }
        switch mode {
        case .list:
            tableView.deselectRow(index)
        case .icons:
            collectionView.deselectItems(at: [IndexPath(item: index, section: 0)])
            onSelectionChange?(selectedItems)
        }
    }

    // MARK: - Branch anchors

    /// Vertical position, in canvas coordinates, where the branch for `name` leaves the
    /// panel: the row's center, clamped to the visible part of the list.
    func branchSourceY(forName name: String) -> CGFloat? {
        guard let canvas = panelView.superview, let index = items.firstIndex(where: { $0.name == name }) else {
            return nil
        }
        let (rect, container): (CGRect, NSScrollView) = switch mode {
        case .list:
            (tableView.convert(tableView.rect(ofRow: index), to: canvas), tableScroll)
        case .icons:
            (
                collectionView.convert(
                    collectionView.layoutAttributesForItem(at: IndexPath(item: index, section: 0))?.frame ?? .zero,
                    to: canvas
                ),
                collectionScroll
            )
        }
        let visible = container.convert(container.bounds, to: canvas)
        return min(max(rect.midY, visible.minY + 8), visible.maxY - 8)
    }

    // MARK: - Actions

    @objc private func modeChanged() {
        show(Mode(rawValue: panelView.modeControl.selectedSegment) ?? .list)
    }

    @objc private func close() {
        onClose?()
    }

    @objc private func openSelectedFiles() {
        for item in selectedItems where !item.isFolder {
            NSWorkspace.shared.open(item.url)
        }
    }

    @objc private func rowsScrolled() {
        onRowsMoved?()
    }

    private func show(_ newMode: Mode) {
        let selection = selectedIndexes
        mode = newMode
        panelView.modeControl.selectedSegment = newMode.rawValue
        tableScroll.isHidden = newMode != .list
        collectionScroll.isHidden = newMode != .icons
        tableView.selectRowIndexes(selection, byExtendingSelection: false)
        collectionView.selectionIndexPaths = Set(selection.map { IndexPath(item: $0, section: 0) })
        onRowsMoved?()
    }

    // MARK: - Setup

    private func setUpTable(name: String) {
        let columns: [(FolderSortKey, CGFloat)] = [(.name, 180), (.size, 70), (.modified, 140)]
        for (key, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key.rawValue))
            column.title = switch key {
            case .name: String(localized: "Name")
            case .size: String(localized: "Size")
            case .modified: String(localized: "Modified")
            }
            column.width = width
            column.minWidth = 50
            column.sortDescriptorPrototype = NSSortDescriptor(key: key.rawValue, ascending: true)
            tableView.addTableColumn(column)
        }
        tableView.style = .fullWidth
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.sortDescriptors = [NSSortDescriptor(key: FolderSortKey.name.rawValue, ascending: true)]
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(openSelectedFiles)
        tableView.setAccessibilityIdentifier("list.\(name)")
        embed(tableView, in: tableScroll)
    }

    private func setUpCollection() {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 96, height: 92)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        collectionView.collectionViewLayout = layout
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.backgroundColors = [.clear]
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(IconItem.self, forItemWithIdentifier: IconItem.identifier)
        embed(collectionView, in: collectionScroll)
    }

    private func embed(_ view: NSView, in scroll: NSScrollView) {
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.frame = panelView.contentView.bounds
        scroll.autoresizingMask = [.width, .height]
        panelView.contentView.addSubview(scroll)
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(rowsScrolled), name: NSView.boundsDidChangeNotification,
            object: scroll.contentView
        )
    }

    private func setUpMessage() {
        messageLabel.alignment = .center
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.isHidden = true
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        panelView.contentView.addSubview(messageLabel)
        NSLayoutConstraint.activate([
            messageLabel.centerYAnchor.constraint(equalTo: panelView.contentView.centerYAnchor),
            messageLabel.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor, constant: 20),
            messageLabel.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor, constant: -20),
        ])
    }
}

// MARK: - List

extension FolderPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let column, items.indices.contains(row) else { return nil }
        let item = items[row]
        let key = FolderSortKey(rawValue: column.identifier.rawValue) ?? .name
        let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView
            ?? FolderCells.makeListCell(identifier: column.identifier, withIcon: key == .name)
        switch key {
        case .name:
            cell.textField?.stringValue = item.name
            cell.imageView?.image = FileIcons.icon(for: item)
        case .size:
            cell.textField?.stringValue = item.entry.kind == .directory
                ? "--" : ByteCountFormatter.string(fromByteCount: item.entry.size, countStyle: .file)
        case .modified:
            cell.textField?.stringValue = item.entry.modified.formatted(date: .numeric, time: .shortened)
        }
        return cell
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard mode == .list else { return }
        onSelectionChange?(selectedItems)
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        guard let descriptor = tableView.sortDescriptors.first,
              let key = descriptor.key.flatMap(FolderSortKey.init(rawValue:)) else { return }
        let selectedNames = Set(selectedItems.map(\.name))
        sortKey = key
        ascending = descriptor.ascending
        items = items.sorted(by: key, ascending: ascending)
        reloadViews(selecting: selectedNames)
    }
}

// MARK: - Icons

extension FolderPanelController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath
    ) -> NSCollectionViewItem {
        let view = collectionView.makeItem(withIdentifier: IconItem.identifier, for: indexPath)
        if let view = view as? IconItem, items.indices.contains(indexPath.item) {
            let item = items[indexPath.item]
            view.imageView?.image = FileIcons.icon(for: item)
            view.textField?.stringValue = item.name
        }
        return view
    }

    func collectionView(_: NSCollectionView, didSelectItemsAt _: Set<IndexPath>) {
        guard mode == .icons else { return }
        onSelectionChange?(selectedItems)
    }

    func collectionView(_: NSCollectionView, didDeselectItemsAt _: Set<IndexPath>) {
        guard mode == .icons else { return }
        onSelectionChange?(selectedItems)
    }
}
