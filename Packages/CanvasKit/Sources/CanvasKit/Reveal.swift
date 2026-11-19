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

    private static func axis(_ low: CGFloat, _ high: CGFloat, _ start: CGFloat, _ length: CGFloat) -> CGFloat {
        if high - low > length || low < start { return low }
        if high > start + length { return high - length }
        return start
    }
}
