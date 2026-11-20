import AppKit
import IndexKit

/// A search panel: filter controls above the matching items from the index. Double-click
/// (or "Show in Canvas") opens a result's folder chain on the canvas.
@MainActor
final class SearchPanelController: NSObject {
    let panelView: PanelView
    private(set) var spec: SearchSpec
    private(set) var results: [SearchResult] = []

    /// Runs a query against the index (off the main thread).
    var search: ((SearchQuery) async -> [SearchResult])?
    /// Show this path on the canvas, with its folder chain.
    var onReveal: ((String) -> Void)?
    var onClose: (() -> Void)?

    var tint: NSColor = .controlAccentColor {
        didSet { tableView.enumerateAvailableRowViews { rowView, _ in rowView.needsDisplay = true } }
    }

    let tableView = NSTableView()
    let filters: SearchFilterBar
    private var generation = 0

    init(spec: SearchSpec, frame: CGRect, tags: [String], roots: [IndexRoot]) {
        self.spec = spec
        panelView = PanelView(frame: frame)
        filters = SearchFilterBar(tags: tags, roots: roots)
        super.init()
        panelView.iconView.image = NSImage(
            systemSymbolName: "magnifyingglass", accessibilityDescription: String(localized: "Search")
        )
        panelView.modeControl.isHidden = true
        panelView.closeButton.target = self
        panelView.closeButton.action = #selector(close)
        panelView.setAccessibilityElement(true)
        panelView.setAccessibilityRole(.group)
        panelView.setAccessibilityIdentifier("searchPanel")
        filters.show(spec)
        filters.onChange = { [weak self] in self?.filtersChanged() }
        setUpViews()
        updateTitle()
    }

    /// Searches for `text`, keeping the filters.
    func setText(_ text: String) {
        guard text != spec.text else { return }
        spec.text = text
        updateTitle()
        refresh()
    }

    /// Runs the search again (the index changed, or the filters did).
    func refresh() {
        generation += 1
        let current = generation
        let query = spec.query()
        Task {
            let found = await search?(query) ?? []
            guard current == generation else { return }
            results = found
            panelView.countLabel.stringValue = String(localized: "\(found.count) results")
            tableView.reloadData()
        }
    }

    private func filtersChanged() {
        spec = filters.apply(to: spec)
        refresh()
    }

    private func updateTitle() {
        panelView.titleLabel.stringValue = spec.title
        panelView.setAccessibilityLabel(spec.title)
    }

    @objc private func close() {
        onClose?()
    }

    @objc private func revealClicked() {
        guard results.indices.contains(tableView.clickedRow) else { return }
        onReveal?(results[tableView.clickedRow].path)
    }

    @objc private func revealSelected() {
        for row in tableView.selectedRowIndexes where results.indices.contains(row) {
            onReveal?(results[row].path)
        }
    }

    @objc private func openSelected() {
        for row in tableView.selectedRowIndexes where results.indices.contains(row) {
            NSWorkspace.shared.open(URL(fileURLWithPath: results[row].path))
        }
    }

    private func setUpViews() {
        let titles = [
            "name": String(localized: "Name"), "folder": String(localized: "Folder"),
            "size": String(localized: "Size"), "modified": String(localized: "Modified"),
        ]
        let widths: KeyValuePairs<String, CGFloat> = ["name": 150, "folder": 140, "size": 70, "modified": 120]
        for (identifier, width) in widths {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = titles[identifier] ?? ""
            column.width = width
            column.minWidth = 50
            tableView.addTableColumn(column)
        }
        tableView.style = .fullWidth
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(revealClicked)
        tableView.setAccessibilityIdentifier("searchResults")
        let menu = NSMenu()
        menu.addItem(
            withTitle: String(localized: "Show in Canvas"),
            action: #selector(revealSelected),
            keyEquivalent: ""
        )
        menu.addItem(withTitle: String(localized: "Open"), action: #selector(openSelected), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        tableView.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let content = panelView.contentView
        for view in [filters, scroll] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            filters.topAnchor.constraint(equalTo: content.topAnchor, constant: 6),
            filters.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            filters.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: filters.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }
}

extension SearchPanelController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        guard let column, results.indices.contains(row) else { return nil }
        let result = results[row]
        let isName = column.identifier.rawValue == "name"
        let cell = tableView.makeView(withIdentifier: column.identifier, owner: nil) as? NSTableCellView
            ?? FolderCells.makeListCell(identifier: column.identifier, withIcon: isName)
        switch column.identifier.rawValue {
        case "name":
            cell.textField?.stringValue = result.name
            cell.imageView?.image = FileIcons.icon(name: result.name, isFolder: result.isDirectory)
        case "folder":
            let folder = (result.path as NSString).deletingLastPathComponent
            cell.textField?.stringValue = (folder as NSString).abbreviatingWithTildeInPath
            cell.toolTip = folder
        case "size":
            cell.textField?.stringValue = ByteCountFormatter.string(fromByteCount: result.totalSize, countStyle: .file)
        default:
            cell.textField?.stringValue = result.modified.formatted(date: .numeric, time: .shortened)
        }
        return cell
    }

    func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
        TintedRowView(tint: tint, sizeFraction: 0)
    }
}
