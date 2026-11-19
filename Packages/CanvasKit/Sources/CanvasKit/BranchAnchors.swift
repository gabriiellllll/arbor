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
                to: CGPoint(x: child.midX, y: child.minY), entering: CGVector(dx: 0, dy: 1)
            )
        case .above:
            return BranchCurve(
                from: CGPoint(x: parent.maxX, y: sourceY), leaving: right,
                to: CGPoint(x: child.midX, y: child.maxY), entering: CGVector(dx: 0, dy: -1)
            )
        }
    }

    private enum Side {
        case right, left, below, above
    }
}
