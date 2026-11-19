import AppKit

/// Cell views for folder panels.
@MainActor
enum FolderCells {
    static func makeListCell(identifier: NSUserInterfaceItemIdentifier, withIcon: Bool) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingMiddle
        text.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(text)
        cell.textField = text
        var constraints = [
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
        ]
        if withIcon {
            let image = NSImageView()
            image.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(image)
            cell.imageView = image
            constraints += [
                image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                image.widthAnchor.constraint(equalToConstant: 16),
                image.heightAnchor.constraint(equalToConstant: 16),
                text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            ]
        } else {
            constraints.append(text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2))
        }
        NSLayoutConstraint.activate(constraints)
        return cell
    }
}

/// Highlights a selected row in the branch color.
@MainActor
final class TintedRowView: NSTableRowView {
    private let tint: NSColor

    init(tint: NSColor) {
        self.tint = tint
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func drawSelection(in _: NSRect) {
        (isEmphasized ? tint : tint.withAlphaComponent(0.35)).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 1), xRadius: 5, yRadius: 5).fill()
    }
}

/// An icon and a name, highlighted in the branch color when selected.
@MainActor
final class IconItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("IconItem")

    var tint: NSColor = .controlAccentColor {
        didSet { updateHighlight() }
    }

    override var isSelected: Bool {
        didSet { updateHighlight() }
    }

    private func updateHighlight() {
        view.layer?.backgroundColor = isSelected ? tint.withAlphaComponent(0.3).cgColor : nil
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        let image = NSImageView()
        let text = NSTextField(labelWithString: "")
        text.alignment = .center
        text.lineBreakMode = .byTruncatingMiddle
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        for subview in [image, text] as [NSView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            image.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            image.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            image.widthAnchor.constraint(equalToConstant: 56),
            image.heightAnchor.constraint(equalToConstant: 56),
            text.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 4),
            text.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
        ])
        imageView = image
        textField = text
    }
}
