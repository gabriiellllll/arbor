import Foundation

/// Reads and writes Finder tags (the same tags Finder shows and Spotlight indexes).
public enum FinderTags {
    public static func tags(of url: URL) throws -> [String] {
        // A fresh URL, so no cached resource value hides a recent change.
        let fresh = URL(fileURLWithPath: url.path)
        return try fresh.resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
    }

    /// `URLResourceValues.tagNames` is read-only in Swift; tags are written through NSURL.
    public static func setTags(_ tags: [String], on url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        try (URL(fileURLWithPath: url.path) as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
    }

    /// Finder behavior: if every item has `tag`, removes it from all; otherwise adds it where
    /// missing. Other tags are kept.
    public static func toggle(_ tag: String, on urls: [URL]) throws {
        let current = try urls.map { try tags(of: $0) }
        let removing = current.allSatisfy { $0.contains(tag) }
        for (url, existing) in zip(urls, current) {
            let updated = removing ? existing
                .filter { $0 != tag } : (existing.contains(tag) ? existing : existing + [tag])
            if updated != existing {
                try setTags(updated, on: url)
            }
        }
    }
}
