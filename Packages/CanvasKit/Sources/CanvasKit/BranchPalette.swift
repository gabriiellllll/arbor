import AppKit

/// Colors for branches. A root panel gets a color index; its sub-branches inherit it.
/// System colors adapt to light and dark mode.
@MainActor
public enum BranchPalette {
    /// Number of colors, usable off the main actor.
    public nonisolated static let count = 8

    public static let colors: [NSColor] = [
        .systemBlue, .systemPurple, .systemPink, .systemOrange,
        .systemGreen, .systemTeal, .systemIndigo, .systemBrown,
    ]

    public static func color(at index: Int) -> NSColor {
        colors[((index % count) + count) % count]
    }

    /// The least used index (lowest first), given the indices already in use.
    public nonisolated static func nextIndex(used: [Int]) -> Int {
        var usage = Array(repeating: 0, count: count)
        for index in used {
            usage[((index % count) + count) % count] += 1
        }
        let least = usage.min() ?? 0
        return usage.firstIndex(of: least) ?? 0
    }
}
