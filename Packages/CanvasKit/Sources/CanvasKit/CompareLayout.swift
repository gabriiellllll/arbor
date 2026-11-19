import CoreGraphics

/// Two folder chains compared side by side: the left chain in one column, the right chain
/// in the next, and homologous panels (same depth) on the same row.
public enum CompareLayout {
    public static let laneGap: CGFloat = 80

    /// `left` and `right` are the panel sizes of each chain, from the compared folder down.
    public static func frames(left: [CGSize], right: [CGSize], origin: CGPoint) -> (left: [CGRect], right: [CGRect]) {
        var rowTops: [CGFloat] = []
        var top = origin.y
        for level in 0 ..< max(left.count, right.count) {
            rowTops.append(top)
            let leftHeight = level < left.count ? left[level].height : 0
            let rightHeight = level < right.count ? right[level].height : 0
            top += max(leftHeight, rightHeight) + LayoutEngine.levelGap
        }
        let rightX = origin.x + (left.map(\.width).max() ?? 0) + laneGap
        let leftFrames = left.enumerated().map {
            CGRect(origin: CGPoint(x: origin.x, y: rowTops[$0.offset]), size: $0.element)
        }
        let rightFrames = right.enumerated().map {
            CGRect(origin: CGPoint(x: rightX, y: rowTops[$0.offset]), size: $0.element)
        }
        return (leftFrames, rightFrames)
    }
}
