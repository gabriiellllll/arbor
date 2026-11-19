import CoreGraphics

/// Cubic Bézier linking a source row in a parent panel to a child panel.
/// Leaves and enters horizontally, like a tree branch growing to the right.
public struct BranchCurve: Equatable, Sendable {
    public static let minimumBend: CGFloat = 40

    public let start: CGPoint
    public let control1: CGPoint
    public let control2: CGPoint
    public let end: CGPoint

    public init(from start: CGPoint, to end: CGPoint) {
        let bend = max(abs(end.x - start.x) / 2, Self.minimumBend)
        self.start = start
        self.end = end
        control1 = CGPoint(x: start.x + bend, y: start.y)
        control2 = CGPoint(x: end.x - bend, y: end.y)
    }

    public var path: CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }
}
