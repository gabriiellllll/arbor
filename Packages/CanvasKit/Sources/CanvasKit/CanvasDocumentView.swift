import AppKit

/// The canvas document. Flipped, so canvas coordinates grow down like the panels' content.
/// While panning (space held or hand tool), it captures every drag and reports it.
@MainActor
public final class CanvasDocumentView: NSView {
    var onPan: ((CGVector) -> Void)?

    var isPanning = false {
        didSet {
            guard isPanning != oldValue else { return }
            window?.invalidateCursorRects(for: self)
            (isPanning ? NSCursor.openHand : NSCursor.arrow).set()
        }
    }

    override public var isFlipped: Bool {
        true
    }

    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard isPanning else {
            let hit = super.hitTest(point)
            // Empty canvas and the branch layer host are not interactive.
            return hit is BranchesView ? self : hit
        }
        return frame.contains(point) ? self : nil
    }

    override public func resetCursorRects() {
        if isPanning {
            addCursorRect(visibleRect, cursor: .openHand)
        }
    }

    override public func mouseDown(with event: NSEvent) {
        guard isPanning else {
            window?.makeFirstResponder(self)
            return
        }
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        var last = event.locationInWindow
        while let next = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]),
              next.type == .leftMouseDragged
        {
            let location = next.locationInWindow
            // Window coordinates grow up; canvas coordinates grow down.
            onPan?(CGVector(dx: location.x - last.x, dy: last.y - location.y))
            last = location
        }
    }

    override public var acceptsFirstResponder: Bool {
        true
    }
}

/// Hosts one shape layer per branch, below the panels.
@MainActor
public final class BranchesView: NSView {
    private var layers: [PanelID: CAShapeLayer] = [:]

    override public var isFlipped: Bool {
        true
    }

    override public init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Shows exactly these branches, keyed by child panel.
    public func setBranches(_ branches: [PanelID: (curve: BranchCurve, color: NSColor)]) {
        for (id, layer) in layers where branches[id] == nil {
            layer.removeFromSuperlayer()
            layers[id] = nil
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, branch) in branches {
            let layer = layers[id] ?? makeLayer(id)
            layer.path = branch.curve.path
            layer.strokeColor = branch.color.cgColor
        }
        CATransaction.commit()
    }

    private func makeLayer(_ id: PanelID) -> CAShapeLayer {
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = 2
        layer.lineCap = .round
        self.layer?.addSublayer(layer)
        layers[id] = layer
        return layer
    }
}
