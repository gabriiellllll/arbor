import CoreGraphics

/// Zoom range of the canvas and the discrete levels used by zoom in / zoom out commands.
public enum Zoom {
    public static let minimum: CGFloat = 0.1
    public static let maximum: CGFloat = 4
    public static let steps: [CGFloat] = [0.1, 0.25, 0.33, 0.5, 0.67, 0.75, 0.9, 1, 1.1, 1.25, 1.5, 2, 3, 4]

    private static let tolerance: CGFloat = 0.001

    public static func clamped(_ scale: CGFloat) -> CGFloat {
        min(max(scale, minimum), maximum)
    }

    /// The first level strictly above `scale`, or the maximum.
    public static func stepIn(from scale: CGFloat) -> CGFloat {
        steps.first { $0 > scale + tolerance } ?? maximum
    }

    /// The last level strictly below `scale`, or the minimum.
    public static func stepOut(from scale: CGFloat) -> CGFloat {
        steps.last { $0 < scale - tolerance } ?? minimum
    }
}
