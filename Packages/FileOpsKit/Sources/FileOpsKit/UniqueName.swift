import Foundation

/// Finder-style "keep both" names: `report.pdf` becomes `report 2.pdf`, then `report 3.pdf`.
public enum UniqueName {
    /// `name` if no name in `taken` matches it (case-insensitively, as on default APFS),
    /// otherwise the first free numbered variant.
    public static func make(for name: String, avoiding taken: Set<String>) -> String {
        let lowered = Set(taken.map { $0.lowercased() })
        guard lowered.contains(name.lowercased()) else { return name }
        let parts = split(name)
        var candidate = parts.number + 1
        while true {
            let next = "\(parts.stem) \(candidate)\(parts.suffix)"
            if !lowered.contains(next.lowercased()) {
                return next
            }
            candidate += 1
        }
    }

    private struct Parts {
        let stem: String
        let number: Int
        let suffix: String
    }

    /// "report 2.pdf" → ("report", 2, ".pdf"); "Photos" → ("Photos", 1, "").
    private static func split(_ name: String) -> Parts {
        let pathExtension = (name as NSString).pathExtension
        // A leading dot starts a name (".env"), not an extension.
        let hasExtension = !pathExtension.isEmpty && name.count > pathExtension.count + 1
        let suffix = hasExtension ? "." + pathExtension : ""
        let base = hasExtension ? String(name.dropLast(suffix.count)) : name
        if let space = base.lastIndex(of: " "), let number = Int(base[base.index(after: space)...]), number > 1 {
            return Parts(stem: String(base[..<space]), number: number, suffix: suffix)
        }
        return Parts(stem: base, number: 1, suffix: suffix)
    }
}
