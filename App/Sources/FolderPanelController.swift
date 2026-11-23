import AppKit
import FileOpsKit
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
    let title: String
    let panelView: PanelView

    /// Branch color: highlights selected rows.
    var tint: NSColor = .controlAccentColor {
        didSet {
            tableView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true }
            collectionView.reloadData()
        }
    }

    /// When compared: the item names of the counterpart folder. Items missing there are marked.
    var counterpartNames: Set<String>? {
        didSet {
            if counterpartNames != oldValue {
                tableView.reloadData(forRowIndexes: IndexSet(items.indices), columnIndexes: [0])
            }
        }
    }

    var items: [FolderItem] = []

    /// Selected items changed (by the user or after a reload).
    var onSelectionChange: (([FolderItem]) -> Void)?
    /// Rows moved inside the panel (scroll, sort, reload, mode): branches must follow.
    var onRowsMoved: (() -> Void)?
    var onClose: (() -> Void)?
    /// "Add to Favorites" was chosen for these folders.
    var onAddFavorites: (([URL]) -> Void)?
    /// Files were dropped: sources, destination folder, copy (rather than move).
    var onDropFiles: (([URL], URL, Bool) -> Void)?
    /// An item was renamed in place.
    var onRename: ((URL, String) -> Void)?
    /// The item whose name is being edited.
    var renamingItem: FolderItem?
    /// Indexed total sizes of the items in a folder (canonical path), by name.
    var sizeLookup: ((String) -> [String: Int64])?
    /// Total sizes of the subfolders, from the index.
    var folderSizes: [String: Int64] = [:]
    /// The folder's items from the catalog, for a disk that is not plugged in, and the disk's name.
    var catalogLookup: ((String) -> (entries: [DirectoryEntry], disk: String)?)?
    /// Set while the folder is shown from the catalog: the disk to plug in. The panel is then
    /// greyed out and read-only.
    var offlineDisk: String?
    /// Draws a bar behind each row, proportional to the item's size.
    var showsSizeBars = false {
        didSet {
            if showsSizeBars != oldValue {
                tableView.reloadData()
            }
        }
    }

    /// Each row's size bar length (files: own size; folders: indexed total).
    var sizeFractions: [Double] {
        SizeBars.fractions(items.map { $0.entry.kind == .directory ? folderSizes[$0.name] ?? 0 : $0.entry.size })
    }

    private(set) var mode: Mode = .list
    var sortKey: FolderSortKey = .name
    var ascending = true
    var loadGeneration = 0

    let tableView = PanelTableView()
    private let tableScroll = NSScrollView()
    let collectionView = NSCollectionView()
    private let collectionScroll = NSScrollView()
    let messageLabel = NSTextField(wrappingLabelWithString: "")
    let offlineBanner = NSTextField(labelWithString: "")

    init(url: URL, frame: CGRect) {
        self.url = url
        canonicalPath = FolderWatcher.canonicalPath(of: url)
        panelView = PanelView(frame: frame)
        let name = FileManager.default.displayName(atPath: url.path)
        title = name
        super.init()
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
        setUpDragAndDrop()
        show(.list)
    }

    var selectedItems: [FolderItem] {
        selectedIndexes.compactMap { items.indices.contains($0) ? items[$0] : nil }
    }

    var selectedIndexes: IndexSet {
        switch mode {
        case .list: tableView.selectedRowIndexes
        case .icons: IndexSet(collectionView.selectionIndexPaths.map(\.item))
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
        tableView.menu = makeContextMenu()

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
        collectionView.menu = makeContextMenu()

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

    /// Greys the items out and shows which disk to plug in, while shown from the catalog.
    func updateOfflineLook() {
        let offline = offlineDisk != nil
        tableScroll.alphaValue = offline ? 0.5 : 1
        collectionScroll.alphaValue = offline ? 0.5 : 1
        offlineBanner.isHidden = !offline
        offlineBanner.stringValue = offlineDisk.map { String(localized: "Plug in “\($0)” to open this folder.") } ?? ""
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
        offlineBanner.alignment = .center
        offlineBanner.font = .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        offlineBanner.drawsBackground = true
        offlineBanner.backgroundColor = .controlBackgroundColor
        offlineBanner.isHidden = true
        offlineBanner.setAccessibilityIdentifier("offlineBanner")
        offlineBanner.translatesAutoresizingMaskIntoConstraints = false
        panelView.contentView.addSubview(offlineBanner)
        NSLayoutConstraint.activate([
            offlineBanner.bottomAnchor.constraint(equalTo: panelView.contentView.bottomAnchor),
            offlineBanner.leadingAnchor.constraint(equalTo: panelView.contentView.leadingAnchor),
            offlineBanner.trailingAnchor.constraint(equalTo: panelView.contentView.trailingAnchor),
            offlineBanner.heightAnchor.constraint(equalToConstant: 24),
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
            let onlyHere = counterpartNames.map { !$0.contains(item.name) } ?? false
            cell.textField?.textColor = onlyHere ? .systemOrange : .labelColor
            cell.toolTip = onlyHere ? String(localized: "Only in \(title)") : nil
            (cell as? NameCell)?.tagsField.attributedStringValue = TagColors.dots(
                for: (try? FinderTags.tags(of: item.url)) ?? []
            )
        case .size:
            let size = item.entry.kind == .directory ? folderSizes[item.name] : item.entry.size
            cell.textField?.stringValue = size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                ?? "--"
        case .modified:
            cell.textField?.stringValue = item.entry.modified.formatted(date: .numeric, time: .shortened)
        }
        return cell
    }

    func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let fractions = showsSizeBars ? sizeFractions : []
        return TintedRowView(tint: tint, sizeFraction: fractions.indices.contains(row) ? fractions[row] : 0)
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
        items = items.sorted(by: key, ascending: ascending, folderSizes: folderSizes)
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
            view.tint = tint
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
