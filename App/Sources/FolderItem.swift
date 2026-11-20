import Foundation
import IndexKit
import UniformTypeIdentifiers

/// A row of a folder panel.
struct FolderItem: Equatable {
    let url: URL
    let entry: DirectoryEntry
    /// Opens as a child panel. Packages (apps, bundles) behave like files, as in Finder.
    let isFolder: Bool

    var name: String {
        entry.name
    }

    init(entry: DirectoryEntry, in folder: URL) {
        self.entry = entry
        url = folder.appendingPathComponent(entry.name, isDirectory: entry.kind == .directory)
        isFolder = entry.kind == .directory && !Self.isPackage(name: entry.name)
    }

    static func isPackage(name: String) -> Bool {
        let pathExtension = (name as NSString).pathExtension
        guard !pathExtension.isEmpty,
              let type = UTType(filenameExtension: pathExtension, conformingTo: .directory) else { return false }
        return type.conforms(to: .package)
    }
}

/// Columns a folder panel can sort by.
enum FolderSortKey: String {
    case name, size, modified
}

extension [FolderItem] {
    /// Sorted by `key`, ties broken by name (Finder order). Folders sort by their indexed total
    /// size from `folderSizes` when known.
    func sorted(by key: FolderSortKey, ascending: Bool, folderSizes: [String: Int64] = [:]) -> [FolderItem] {
        sorted { lhs, rhs in
            let byName = lhs.name.localizedStandardCompare(rhs.name)
            let order: ComparisonResult = switch key {
            case .name:
                byName
            case .size:
                ordering(folderSizes[lhs.name] ?? lhs.entry.size, folderSizes[rhs.name] ?? rhs.entry.size) ?? byName
            case .modified:
                ordering(lhs.entry.modified, rhs.entry.modified) ?? byName
            }
            return ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
}

/// Nil when equal, so the caller can break the tie.
private func ordering<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult? {
    lhs == rhs ? nil : (lhs < rhs ? .orderedAscending : .orderedDescending)
}
