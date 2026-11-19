import CoreGraphics

/// Where a new child panel goes when it opens from a row of its parent.
public enum PanelPlacement {
    public static let horizontalGap: CGFloat = 80
    public static let verticalGap: CGFloat = 24
    /// Distance from the child's top edge to the point its branch attaches to.
    public static let titleOffset: CGFloat = 18

    /// Right of the parent, title aligned with the source row, then pushed down until it
    /// overlaps nothing in `avoiding`.
    // ponytail: pushes down only; phase 2 layouts replace this with full overlap removal.
    public static func childFrame(parent: CGRect, sourceY: CGFloat, size: CGSize, avoiding: [CGRect]) -> CGRect {
        var frame = CGRect(
            origin: CGPoint(x: parent.maxX + horizontalGap, y: sourceY - titleOffset),
            size: size
        )
        while let blocker = avoiding.first(where: { $0.intersects(frame.insetBy(dx: 0, dy: -verticalGap / 2)) }) {
            frame.origin.y = blocker.maxY + verticalGap
        }
        return frame
    }
}
