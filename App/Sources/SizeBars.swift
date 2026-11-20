import Foundation

/// Lengths of the size bars drawn behind rows: each item's size relative to the largest in
/// its folder.
enum SizeBars {
    /// Fractions from 0 to 1, in the order of `sizes`; all zero when nothing has a size.
    static func fractions(_ sizes: [Int64]) -> [Double] {
        let largest = sizes.max() ?? 0
        guard largest > 0 else { return sizes.map { _ in 0 } }
        return sizes.map { Double(max($0, 0)) / Double(largest) }
    }
}
