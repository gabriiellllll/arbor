import CoreGraphics

/// Where a branch leaves its parent and reaches its child, from where the panels are, so
/// branches stay attached in every layout, including manual.
public enum BranchAnchors {
    /// The branch from the source row (at `sourceY` in the parent) to the child's title.
    /// It leaves through the parent's side facing the child (right unless the child is
    /// clearly to the left) and enters the child's side facing the parent.
    public static func curve(parent: CGRect, sourceY: CGFloat, child: CGRect) -> BranchCurve {
        let gaps: [(Side, CGFloat)] = [
            (.right, child.minX - parent.maxX),
            (.left, parent.minX - child.maxX),
            (.below, child.minY - parent.maxY),
            (.above, parent.minY - child.maxY),
        ]
        let side = gaps.max { $0.1 < $1.1 }.flatMap { $0.1 > 0 ? $0.0 : nil } ?? .right
        let titleY = child.minY + PanelPlacement.titleOffset
        let right = CGVector(dx: 1, dy: 0)
        let left = CGVector(dx: -1, dy: 0)
        switch side {
        case .right:
            return BranchCurve(
                from: CGPoint(x: parent.maxX, y: sourceY), leaving: right,
                to: CGPoint(x: child.minX, y: titleY), entering: right
            )
        case .left:
            return BranchCurve(
                from: CGPoint(x: parent.minX, y: sourceY), leaving: left,
                to: CGPoint(x: child.maxX, y: titleY), entering: left
            )
        case .below:
            return BranchCurve(
                from: CGPoint(x: parent.maxX, y: sourceY), leaving: right,
                to: CGPoint(x: verticalEntryX(parent: parent, child: child), y: child.minY),
                entering: CGVector(dx: 0, dy: 1)
            )
        case .above:
            return BranchCurve(
                from: CGPoint(x: parent.maxX, y: sourceY), leaving: right,
                to: CGPoint(x: verticalEntryX(parent: parent, child: child), y: child.maxY),
                entering: CGVector(dx: 0, dy: -1)
            )
        }
    }

    /// Inset of a top or bottom entry point from the child's corners.
    static let cornerInset: CGFloat = 20

    /// Where a branch leaving the parent's right edge enters a child above or below: the
    /// child's center if it lies right of the parent, otherwise as far right of the parent as
    /// the child allows, so the branch never loops back behind the parent.
    private static func verticalEntryX(parent: CGRect, child: CGRect) -> CGFloat {
        let clear = parent.maxX + BranchCurve.minimumBend
        guard child.midX < clear else { return child.midX }
        return min(max(clear, child.minX + cornerInset), child.maxX - cornerInset)
    }

    private enum Side {
        case right, left, below, above
    }
}
