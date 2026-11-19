import CoreGraphics

/// Computes how to scroll the canvas so a target rectangle becomes visible.
public enum Reveal {
    /// The origin for the visible rectangle that shows `target` (plus `margin`) with the
    /// smallest movement. A target larger than the visible area is aligned top-left.
    public static func origin(revealing target: CGRect, in visible: CGRect, margin: CGFloat = 40) -> CGPoint {
        let padded = target.insetBy(dx: -margin, dy: -margin)
        return CGPoint(
            x: axis(padded.minX, padded.maxX, visible.minX, visible.width),
            y: axis(padded.minY, padded.maxY, visible.minY, visible.height)
        )
    }

    /// Like `origin(revealing:in:margin:)`, but shows `context` too (for example the parent
    /// of a new panel) when `target` and `context` fit on screen together.
    public static func origin(
        revealing target: CGRect, withContext context: CGRect, in visible: CGRect, margin: CGFloat = 40
    ) -> CGPoint {
        let both = target.union(context).insetBy(dx: -margin, dy: -margin)
        let fits = both.width <= visible.width && both.height <= visible.height
        return origin(revealing: fits ? target.union(context) : target, in: visible, margin: margin)
    }

    private static func axis(_ low: CGFloat, _ high: CGFloat, _ start: CGFloat, _ length: CGFloat) -> CGFloat {
        if high - low > length || low < start {
            return low
        }
        if high > start + length {
            return high - length
        }
        return start
    }
}
