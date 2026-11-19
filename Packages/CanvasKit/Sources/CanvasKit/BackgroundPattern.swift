import CoreGraphics

/// Canvas background styles.
public enum CanvasBackground: String, CaseIterable, Codable, Sendable {
    case dots, grid, crosses, plain
}

/// Geometry of the repeating background pattern, in canvas coordinates.
public enum BackgroundPattern {
    public static let baseSpacing: CGFloat = 24
    /// Below this on-screen distance the pattern becomes noise, so spacing doubles.
    public static let minimumScreenSpacing: CGFloat = 12

    public static func spacing(forScale scale: CGFloat) -> CGFloat {
        var spacing = baseSpacing
        while spacing * scale < minimumScreenSpacing {
            spacing *= 2
        }
        return spacing
    }

    /// Multiples of `spacing` within `[low, high]`.
    public static func positions(from low: CGFloat, to high: CGFloat, spacing: CGFloat) -> [CGFloat] {
        let first = (low / spacing).rounded(.up)
        let last = (high / spacing).rounded(.down)
        guard first <= last else { return [] }
        return stride(from: first, through: last, by: 1).map { $0 * spacing }
    }
}
