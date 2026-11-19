import AppKit

/// Draws the background pattern for the visible part of the canvas, in screen space, so the
/// pattern stays crisp at any zoom.
@MainActor
final class CanvasBackgroundView: NSView {
    var style: CanvasBackground = .dots {
        didSet { needsDisplay = true }
    }

    var canvasRect: CGRect = .zero {
        didSet { needsDisplay = true }
    }

    var magnification: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    override var isFlipped: Bool {
        true
    }

    override func draw(_: NSRect) {
        NSColor.underPageBackgroundColor.setFill()
        bounds.fill()
        guard style != .plain, canvasRect.width > 0 else { return }

        let spacing = BackgroundPattern.spacing(forScale: magnification)
        let xs = BackgroundPattern.positions(from: canvasRect.minX, to: canvasRect.maxX, spacing: spacing)
            .map { ($0 - canvasRect.minX) * magnification }
        let ys = BackgroundPattern.positions(from: canvasRect.minY, to: canvasRect.maxY, spacing: spacing)
            .map { ($0 - canvasRect.minY) * magnification }

        switch style {
        case .dots: drawDots(xs: xs, ys: ys)
        case .grid: drawGrid(xs: xs, ys: ys)
        case .crosses: drawCrosses(xs: xs, ys: ys)
        case .plain: break
        }
    }

    private func drawDots(xs: [CGFloat], ys: [CGFloat]) {
        let path = NSBezierPath()
        for x in xs {
            for y in ys {
                path.appendOval(in: CGRect(x: x - 1, y: y - 1, width: 2, height: 2))
            }
        }
        NSColor.tertiaryLabelColor.setFill()
        path.fill()
    }

    private func drawGrid(xs: [CGFloat], ys: [CGFloat]) {
        let path = NSBezierPath()
        for x in xs {
            path.move(to: CGPoint(x: x, y: 0))
            path.line(to: CGPoint(x: x, y: bounds.maxY))
        }
        for y in ys {
            path.move(to: CGPoint(x: 0, y: y))
            path.line(to: CGPoint(x: bounds.maxX, y: y))
        }
        path.lineWidth = 0.5
        NSColor.separatorColor.setStroke()
        path.stroke()
    }

    private func drawCrosses(xs: [CGFloat], ys: [CGFloat]) {
        let path = NSBezierPath()
        for x in xs {
            for y in ys {
                path.move(to: CGPoint(x: x - 3, y: y))
                path.line(to: CGPoint(x: x + 3, y: y))
                path.move(to: CGPoint(x: x, y: y - 3))
                path.line(to: CGPoint(x: x, y: y + 3))
            }
        }
        path.lineWidth = 1
        NSColor.tertiaryLabelColor.setStroke()
        path.stroke()
    }
}
