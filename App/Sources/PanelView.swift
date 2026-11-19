import AppKit

/// The chrome of a panel on the canvas: rounded card, title bar (drag to move), resize
/// handle, and an accent border when active. Content goes in `contentView`.
@MainActor
final class PanelView: NSView {
    static let titleBarHeight: CGFloat = 36
    static let minimumSize = CGSize(width: 240, height: 160)

    let iconView = NSImageView()
    let titleLabel = NSTextField(labelWithString: "")
    let countLabel = NSTextField(labelWithString: "")
    let modeControl = NSSegmentedControl()
    let closeButton = NSButton()
    let contentView = NSView()

    /// Called continuously while the panel moves or resizes.
    var onFrameChanging: (() -> Void)?
    /// Called once a move or resize ends.
    var onFrameChanged: (() -> Void)?
    /// Called on any click inside the panel.
    var onActivate: (() -> Void)?

    var isActive = false {
        didSet { updateBorder() }
    }

    private let titleBar = PanelTitleBar()
    private let resizeHandle = PanelResizeHandle()

    override var isFlipped: Bool {
        true
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        updateBorder()

        titleBar.frame = CGRect(x: 0, y: 0, width: frame.width, height: Self.titleBarHeight)
        titleBar.autoresizingMask = [.width]
        titleBar.onDrag = { [weak self] delta in self?.move(by: delta) }
        titleBar.onDragEnd = { [weak self] in self?.onFrameChanged?() }
        addSubview(titleBar)
        setUpTitleBar()

        contentView.frame = CGRect(
            x: 0, y: Self.titleBarHeight, width: frame.width, height: frame.height - Self.titleBarHeight
        )
        contentView.autoresizingMask = [.width, .height]
        addSubview(contentView)

        resizeHandle.frame = CGRect(x: frame.width - 14, y: frame.height - 14, width: 14, height: 14)
        resizeHandle.autoresizingMask = [.minXMargin, .minYMargin]
        resizeHandle.onDrag = { [weak self] delta in self?.resize(by: delta) }
        resizeHandle.onDragEnd = { [weak self] in self?.onFrameChanged?() }
        addSubview(resizeHandle)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUpTitleBar() {
        iconView.imageScaling = .scaleProportionallyDown
        titleLabel.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor

        modeControl.segmentCount = 2
        modeControl.setImage(
            NSImage(systemSymbolName: "list.bullet", accessibilityDescription: String(localized: "List")),
            forSegment: 0
        )
        modeControl.setImage(
            NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: String(localized: "Icons")),
            forSegment: 1
        )
        modeControl.trackingMode = .selectOne
        modeControl.segmentStyle = .texturedRounded
        modeControl.controlSize = .small
        modeControl.selectedSegment = 0

        closeButton.image = NSImage(
            systemSymbolName: "xmark",
            accessibilityDescription: String(localized: "Close Panel")
        )
        closeButton.isBordered = false
        closeButton.toolTip = String(localized: "Close Panel")

        let stack = NSStackView(views: [iconView, titleLabel, countLabel, modeControl, closeButton])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.setCustomSpacing(10, after: countLabel)
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        titleBar.addSubview(stack)
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: titleBar.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: titleBar.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: titleBar.centerYAnchor),
        ])
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit != nil, NSApp.currentEvent?.type == .leftMouseDown {
            onActivate?()
        }
        return hit
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        }
        updateBorder()
    }

    private func updateBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderColor = (isActive ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
            layer?.borderWidth = isActive ? 2 : 1
        }
    }

    private func move(by delta: CGVector) {
        setFrameOrigin(CGPoint(x: frame.minX + delta.dx, y: frame.minY + delta.dy))
        onFrameChanging?()
    }

    private func resize(by delta: CGVector) {
        setFrameSize(CGSize(
            width: max(Self.minimumSize.width, frame.width + delta.dx),
            height: max(Self.minimumSize.height, frame.height + delta.dy)
        ))
        onFrameChanging?()
    }
}

/// Reports mouse drags in the coordinates of the canvas (the panel's superview), so moves
/// and resizes stay correct at any zoom.
@MainActor
class PanelDragView: NSView {
    var onDrag: ((CGVector) -> Void)?
    var onDragEnd: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        guard let canvas = superview?.superview else { return }
        var last = canvas.convert(event.locationInWindow, from: nil)
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]),
              next.type == .leftMouseDragged
        {
            let location = canvas.convert(next.locationInWindow, from: nil)
            onDrag?(CGVector(dx: location.x - last.x, dy: location.y - last.y))
            last = location
        }
        onDragEnd?()
    }
}

@MainActor
final class PanelTitleBar: PanelDragView {
    override var isFlipped: Bool {
        true
    }

    override func draw(_: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        CGRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
    }
}

@MainActor
final class PanelResizeHandle: PanelDragView {
    override func draw(_: NSRect) {
        let path = NSBezierPath()
        for offset in [4.0, 8.0] {
            path.move(to: CGPoint(x: bounds.maxX - offset, y: bounds.minY + 2))
            path.line(to: CGPoint(x: bounds.maxX - 2, y: bounds.minY + offset))
        }
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }
}
