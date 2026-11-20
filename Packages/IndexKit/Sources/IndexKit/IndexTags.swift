import Darwin
import Foundation
import GRDB

/// Reads Finder tags straight from their extended attribute: much cheaper than resource
/// values when done for every file of a volume.
public enum TagReader {
    private static let attribute = "com.apple.metadata:_kMDItemUserTags"

    /// Tag names (Finder stores "Name\ncolor index"; only names are returned).
    public static func tags(atPath path: String) -> [String] {
        let size = getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0 else { return [] }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, attribute, $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard read > 0,
              let values = try? PropertyListSerialization
                  .propertyList(from: data.prefix(read), format: nil) as? [String]
        else { return [] }
        return values.compactMap { $0.split(separator: "\n").first.map(String.init) }
    }
}

public struct TagCount: Equatable, Sendable {
    public let name: String
    public let count: Int
}

extension IndexStore {
    /// Every tag in the index, with how many items carry it, by name.
    public func tagCounts() throws -> [TagCount] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT name, COUNT(*) AS count FROM tag GROUP BY name ORDER BY name").map {
                TagCount(name: $0["name"], count: $0["count"])
            }
        }
    }

    /// Replaces the tags of the direct children of `folder`, read from disk.
    func readTags(ofChildrenOf folder: IndexScanner.Folder) throws {
        try writer.write { db in try Self.readTags(ofChildrenOf: folder, db) }
    }

    static func readTags(ofChildrenOf folder: IndexScanner.Folder, _ db: Database) throws {
        let children = try Row.fetchAll(db, sql: "SELECT id, name FROM item WHERE parent = ?", arguments: [folder.id])
        for child in children {
            let id: Int64 = child["id"]
            try db.execute(sql: "DELETE FROM tag WHERE itemID = ?", arguments: [id])
            let path = (folder.path as NSString).appendingPathComponent(child["name"])
            for name in Set(TagReader.tags(atPath: path)) {
                try db.execute(sql: "INSERT INTO tag (itemID, name) VALUES (?, ?)", arguments: [id, name])
            }
        }
    }
}

extension IndexScanner {
    /// Reads the Finder tags of everything indexed under `root` (a background pass after a
    /// scan, so tags never slow the scan itself).
    public func readTags(_ root: IndexRoot, control: ScanControl = ScanControl()) throws {
        try readTags(below: Folder(id: root.itemID, path: root.path, depth: 0), control: control)
        try store.writer.write { db in
            try db.execute(
                sql: "UPDATE root SET tagsReadAt = ? WHERE id = ?", arguments: [Date().timeIntervalSince1970, root.id]
            )
        }
    }

    /// Reads the tags of everything below `folder`, folder by folder.
    func readTags(below folder: Folder, control: ScanControl) throws {
        var pending = [folder]
        while !pending.isEmpty {
            if control.isCancelled {
                throw CancellationError()
            }
            let batch = Array(pending.suffix(200))
            pending.removeLast(batch.count)
            pending += try store.writer.write { db in
                var subfolders: [Folder] = []
                for parent in batch {
                    try IndexStore.readTags(ofChildrenOf: parent, db)
                    subfolders += try Row.fetchAll(
                        db, sql: "SELECT id, name FROM item WHERE parent = ? AND kind = ?",
                        arguments: [parent.id, IndexStore.Kind.directory.rawValue]
                    ).map {
                        Folder(
                            id: $0["id"], path: (parent.path as NSString).appendingPathComponent($0["name"]),
                            depth: parent.depth + 1
                        )
                    }
                }
                return subfolders
            }
        }
    }
}
