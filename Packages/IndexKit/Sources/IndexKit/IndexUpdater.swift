import Foundation
import GRDB

/// Keeps the index in sync with folder changes (from FSEvents): re-reads changed folders,
/// indexes new subtrees, drops removed ones, and adds up sizes along the parent chain.
public struct IndexUpdater: Sendable {
    let store: IndexStore

    public init(store: IndexStore) {
        self.store = store
    }

    /// Applies `changes` and returns the folders whose contents or sizes changed.
    @discardableResult
    public func apply(_ changes: [FolderChange]) throws -> Set<String> {
        var affected: Set<String> = []
        let rescans = Set(changes.filter(\.mustRescanSubfolders).map(\.path))
        for path in Set(changes.map(\.path)) {
            guard let root = try store.root(containing: path), !Self.isExcluded(path, root),
                  let folder = try nearestIndexedFolder(
                      of: path,
                      in: root
                  ) else { continue }
            if rescans.contains(path) {
                try rescan(folder, root: root)
            } else {
                try refresh(folder, root: root)
            }
            affected.insert(folder.path)
        }
        return affected
    }

    private static func isExcluded(_ path: String, _ root: IndexRoot) -> Bool {
        root.exclusions.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    /// The closest folder at or above `path` that exists on disk and in the index.
    private func nearestIndexedFolder(of path: String, in root: IndexRoot) throws -> IndexScanner.Folder? {
        var candidate = path
        while true {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate, isDirectory: &isDirectory), isDirectory.boolValue,
               let id = try store.itemID(forPath: candidate),
               let depth = try store.writer.read({ db in
                   try Int.fetchOne(db, sql: "SELECT depth FROM item WHERE id = ?", arguments: [id])
               })
            {
                return IndexScanner.Folder(id: id, path: candidate, depth: depth)
            }
            guard candidate != root.path, candidate != "/" else { return nil }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
    }

    /// Drops everything below `folder` and scans it again.
    private func rescan(_ folder: IndexScanner.Folder, root: IndexRoot) throws {
        try store.writer
            .write { db in try db.execute(sql: "DELETE FROM item WHERE parent = ?", arguments: [folder.id]) }
        let scanner = IndexScanner(store: store)
        _ = try scanner.scanSubtree(folder, root: root, control: ScanControl(), progress: { _ in })
        try store.aggregate(subtreeOf: folder.id)
        try scanner.readTags(below: folder, control: ScanControl())
        try store.propagateUp(from: folder.id)
    }

    /// Re-reads one folder: adds, updates and removes its direct items; new subfolders are
    /// scanned in full.
    private func refresh(_ folder: IndexScanner.Folder, root: IndexRoot) throws {
        let entries = try DirectoryReader.entries(at: URL(fileURLWithPath: folder.path)).filter {
            !Self.isExcluded((folder.path as NSString).appendingPathComponent($0.name), root)
        }
        var newFolders: [IndexScanner.Folder] = []
        try store.writer.write { db in
            var existing: [String: Row] = [:]
            for row in try Row.fetchAll(
                db, sql: "SELECT id, name, kind, size, modified FROM item WHERE parent = ?", arguments: [folder.id]
            ) {
                existing[row["name"]] = row
            }
            var added: [DirectoryEntry] = []
            for entry in entries {
                let kind = IndexStore.Kind(entry.kind).rawValue
                guard let row = existing.removeValue(forKey: entry.name) else {
                    added.append(entry)
                    continue
                }
                if row["kind"] != kind {
                    try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [row["id"]])
                    added.append(entry)
                } else if kind != IndexStore.Kind.directory.rawValue,
                          row["size"] != entry.size || row["modified"] != entry.modified.timeIntervalSince1970
                {
                    try db.execute(sql: """
                    UPDATE item SET size = ?1, allocated = ?2, totalSize = ?1, totalAllocated = ?2, modified = ?3
                    WHERE id = ?4
                    """, arguments: [entry.size, entry.allocatedSize, entry.modified.timeIntervalSince1970, row["id"]])
                }
            }
            for row in existing.values {
                try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [row["id"]])
            }
            let ids = try IndexStore.insert(added, parent: folder.id, rootID: root.id, depth: folder.depth + 1, db)
            for (entry, id) in zip(added, ids) where entry.kind == .directory && !entry.isMountPoint {
                let path = (folder.path as NSString).appendingPathComponent(entry.name)
                newFolders.append(IndexScanner.Folder(id: id, path: path, depth: folder.depth + 1))
            }
        }
        let scanner = IndexScanner(store: store)
        for newFolder in newFolders {
            _ = try scanner.scanSubtree(newFolder, root: root, control: ScanControl(), progress: { _ in })
            try store.aggregate(subtreeOf: newFolder.id)
            try scanner.readTags(below: newFolder, control: ScanControl())
        }
        // Tag changes only touch an extended attribute (dates don't change): re-read them all.
        try store.readTags(ofChildrenOf: folder)
        try store.propagateUp(from: folder.id)
    }
}
