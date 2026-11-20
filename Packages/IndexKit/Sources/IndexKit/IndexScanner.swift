import Foundation
import GRDB

/// Cancels a scan from another thread.
public final class ScanControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.withLock { cancelled = true }
    }

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }
}

public struct ScanSummary: Equatable, Sendable {
    /// Items indexed (the root folder itself excluded).
    public let items: Int
    /// Folders that could not be read (permissions), not descended into.
    public let unreadable: [String]
}

/// Scans folder trees into the index with `getattrlistbulk`, then adds up folder sizes from
/// the bottom. Does not follow symbolic links, cross mount points, or enter exclusions.
public struct IndexScanner: Sendable {
    /// Folders read per write transaction.
    private static let foldersPerTransaction = 500

    let store: IndexStore

    public init(store: IndexStore) {
        self.store = store
    }

    /// Replaces everything indexed under `root` with a fresh scan.
    @discardableResult
    public func scan(
        _ root: IndexRoot, control: ScanControl = ScanControl(), progress: @Sendable (Int) -> Void = { _ in }
    ) throws -> ScanSummary {
        try store.writer.write { db in
            try db.execute(sql: "DELETE FROM item WHERE parent = ?", arguments: [root.itemID])
            try db.execute(
                sql: "UPDATE item SET size = 0, allocated = 0 WHERE id = ?", arguments: [root.itemID]
            )
        }
        let summary = try scanSubtree(
            Folder(id: root.itemID, path: root.path, depth: 0), root: root, control: control, progress: progress
        )
        try store.aggregate(subtreeOf: root.itemID)
        return summary
    }

    /// An indexed folder to read.
    struct Folder {
        let id: Int64
        let path: String
        let depth: Int
    }

    /// Scans the contents of an indexed folder (already emptied) and everything below it.
    /// Sizes are not aggregated.
    func scanSubtree(
        _ folder: Folder, root: IndexRoot, control: ScanControl, progress: @Sendable (Int) -> Void
    ) throws -> ScanSummary {
        let exclusions = Set(root.exclusions)
        var pending = [folder]
        var count = 0
        var unreadable: [String] = []
        while !pending.isEmpty {
            if control.isCancelled {
                throw CancellationError()
            }
            try store.writer.write { db in
                for _ in 0 ..< Self.foldersPerTransaction {
                    guard let next = pending.popLast() else { return }
                    guard let all = try? DirectoryReader.entries(at: URL(fileURLWithPath: next.path)) else {
                        unreadable.append(next.path)
                        continue
                    }
                    // Excluded items are left out entirely (an excluded folder has no known size).
                    let entries = exclusions.isEmpty ? all : all.filter {
                        !exclusions.contains((next.path as NSString).appendingPathComponent($0.name))
                    }
                    let ids = try IndexStore.insert(
                        entries,
                        parent: next.id,
                        rootID: root.id,
                        depth: next.depth + 1,
                        db
                    )
                    count += entries.count
                    for (entry, id) in zip(entries, ids) where entry.kind == .directory && !entry.isMountPoint {
                        let path = (next.path as NSString).appendingPathComponent(entry.name)
                        pending.append(Folder(id: id, path: path, depth: next.depth + 1))
                    }
                }
            }
            progress(count)
        }
        return ScanSummary(items: count, unreadable: unreadable)
    }
}

extension IndexStore {
    /// Recomputes folder totals below and including `id`, deepest folders first.
    func aggregate(subtreeOf id: Int64) throws {
        try writer.write { db in
            let folders = try Int64.fetchAll(db, sql: """
            WITH RECURSIVE sub(id, depth) AS (
                SELECT id, depth FROM item WHERE id = ?
                UNION ALL
                SELECT item.id, item.depth FROM item JOIN sub ON item.parent = sub.id WHERE item.kind = ?
            )
            SELECT id FROM sub ORDER BY depth DESC
            """, arguments: [id, Kind.directory.rawValue])
            for folder in folders {
                try Self.recomputeTotals(folder, db)
            }
        }
    }

    /// Recomputes the totals of `id` and every folder above it.
    func propagateUp(from id: Int64) throws {
        try writer.write { db in
            var current: Int64? = id
            while let folder = current {
                try Self.recomputeTotals(folder, db)
                current = try Int64.fetchOne(db, sql: "SELECT parent FROM item WHERE id = ?", arguments: [folder])
            }
        }
    }

    private static func recomputeTotals(_ id: Int64, _ db: Database) throws {
        try db.cachedStatement(sql: """
        UPDATE item SET
            totalSize = size + COALESCE((SELECT SUM(totalSize) FROM item AS child WHERE child.parent = ?1), 0),
            totalAllocated = allocated
                + COALESCE((SELECT SUM(totalAllocated) FROM item AS child WHERE child.parent = ?1), 0),
            descendants = COALESCE((SELECT COUNT(*) + SUM(descendants) FROM item AS child WHERE child.parent = ?1), 0)
        WHERE id = ?1
        """).execute(arguments: [id])
    }
}
