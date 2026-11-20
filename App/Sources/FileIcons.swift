import AppKit
import UniformTypeIdentifiers

/// File icons by type, cached per extension. Asking the workspace for each file's own icon
/// is too slow for large folders; only packages (apps, bundles) get their own icon.
@MainActor
enum FileIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: FolderItem) -> NSImage {
        if item.entry.kind == .directory, !item.isFolder {
            return NSWorkspace.shared.icon(forFile: item.url.path)
        }
        return icon(name: item.name, isFolder: item.isFolder)
    }

    static func icon(name: String, isFolder: Bool) -> NSImage {
        let key = isFolder ? "/folder" : (name as NSString).pathExtension.lowercased()
        if let icon = cache[key] {
            return icon
        }
        let type: UTType = isFolder ? .folder : (UTType(filenameExtension: key) ?? .data)
        let icon = NSWorkspace.shared.icon(for: type)
        cache[key] = icon
        return icon
    }
}
