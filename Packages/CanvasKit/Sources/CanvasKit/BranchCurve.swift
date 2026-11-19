import CoreGraphics

/// Cubic Bézier linking a source row in a parent panel to a child panel.
/// Leaves and enters horizontally, like a tree branch growing to the right.
public struct BranchCurve: Equatable, Sendable {
    public static let minimumBend: CGFloat = 40

    public let start: CGPoint
    public let control1: CGPoint
    public let control2: CGPoint
    public let end: CGPoint

    /// Leaves rightward and enters rightward.
    public init(from start: CGPoint, to end: CGPoint) {
        self.init(from: start, leaving: CGVector(dx: 1, dy: 0), to: end, entering: CGVector(dx: 1, dy: 0))
    }

    /// Leaves `start` along `leaving` and reaches `end` moving along `entering` (unit vectors).
    /// Each control point sits half the distance along its direction, at least `minimumBend`.
    public init(from start: CGPoint, leaving: CGVector, to end: CGPoint, entering: CGVector) {
        let delta = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let startBend = max(abs(delta.dx * leaving.dx + delta.dy * leaving.dy) / 2, Self.minimumBend)
        let endBend = max(abs(delta.dx * entering.dx + delta.dy * entering.dy) / 2, Self.minimumBend)
        self.start = start
        self.end = end
        control1 = CGPoint(x: start.x + leaving.dx * startBend, y: start.y + leaving.dy * startBend)
        control2 = CGPoint(x: end.x - entering.dx * endBend, y: end.y - entering.dy * endBend)
    }

    public var path: CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        return path
    }
}
