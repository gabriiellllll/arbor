import Foundation
import GRDB

/// A folder tree the index covers (a volume or a folder).
public struct IndexRoot: Equatable, Sendable {
    public let id: Int64
    public let path: String
    /// The item representing the root folder itself.
    public let itemID: Int64
    /// Paths skipped by scans.
    public let exclusions: [String]
    public let volumeUUID: String?
    /// The last FSEvents event applied; changes after it are caught up on launch.
    public let lastEventID: UInt64?
    public let scannedAt: Date?
    /// When Finder tags were last read for the whole root.
    public let tagsReadAt: Date?
}

/// An indexed file or folder. For folders, `totalSize` and `totalAllocated` include everything
/// below; for files they equal their own sizes.
public struct IndexedItem: Equatable, Sendable {
    public let id: Int64
    public let parent: Int64?
    public let name: String
    public let isDirectory: Bool
    public let size: Int64
    public let totalSize: Int64
    public let totalAllocated: Int64
    /// Number of items below (folders only).
    public let descendants: Int64
    public let modified: Date
}

/// The file index, in SQLite. Items are stored by parent and name (no full paths), which keeps
/// the database small for millions of entries; a path resolves component by component.
public final class IndexStore: Sendable {
    let writer: any DatabaseWriter

    private init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// WAL database: the UI reads while scans write.
    public static func open(at url: URL) throws -> IndexStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        // Another connection may be finishing a write (a second app instance, a closing store).
        configuration.busyMode = .timeout(5)
        return try IndexStore(DatabasePool(path: url.path, configuration: configuration))
    }

    public static func inMemory() throws -> IndexStore {
        try IndexStore(DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "item") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("parent", .integer).references("item", onDelete: .cascade)
                table.column("rootID", .integer).notNull()
                table.column("name", .text).notNull()
                table.column("kind", .integer).notNull()
                table.column("fileID", .integer)
                table.column("size", .integer).notNull()
                table.column("allocated", .integer).notNull()
                table.column("totalSize", .integer).notNull()
                table.column("totalAllocated", .integer).notNull()
                table.column("descendants", .integer).notNull().defaults(to: 0)
                table.column("created", .double)
                table.column("modified", .double)
                table.column("hidden", .boolean).notNull()
                table.column("depth", .integer).notNull()
                table.uniqueKey(["parent", "name"])
            }
            try db.create(index: "item_root_depth", on: "item", columns: ["rootID", "depth"])
            try db.create(table: "root") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("path", .text).notNull().unique()
                table.column("itemID", .integer).notNull().references("item", onDelete: .cascade)
                table.column("exclusions", .text).notNull()
                table.column("volumeUUID", .text)
                table.column("lastEventID", .integer)
                table.column("scannedAt", .double)
            }
        }
        migrator.registerMigration("v2-search") { db in
            // Name search: words split at separators, accents and case ignored, fast prefixes.
            // ponytail: triggers slow full scans by a third (49k → 33k items/s); if it matters, skip
            // them during full scans and run `INSERT INTO item_name(item_name) VALUES ('rebuild')` after.
            try db.execute(sql: """
            CREATE VIRTUAL TABLE item_name USING fts5(
                name, content = 'item', content_rowid = 'id',
                tokenize = "unicode61 remove_diacritics 2", prefix = '1 2 3'
            );
            CREATE TRIGGER item_name_insert AFTER INSERT ON item BEGIN
                INSERT INTO item_name(rowid, name) VALUES (new.id, new.name);
            END;
            CREATE TRIGGER item_name_delete AFTER DELETE ON item BEGIN
                INSERT INTO item_name(item_name, rowid, name) VALUES ('delete', old.id, old.name);
            END;
            CREATE TRIGGER item_name_update AFTER UPDATE OF name ON item BEGIN
                INSERT INTO item_name(item_name, rowid, name) VALUES ('delete', old.id, old.name);
                INSERT INTO item_name(rowid, name) VALUES (new.id, new.name);
            END;
            INSERT INTO item_name(item_name) VALUES ('rebuild');
            """)
        }
        migrator.registerMigration("v3-tags") { db in
            try db.create(table: "tag", options: [.withoutRowID]) { table in
                table.column("itemID", .integer).notNull().references("item", onDelete: .cascade)
                table.column("name", .text).notNull()
                table.primaryKey(["itemID", "name"])
            }
            try db.create(index: "tag_name", on: "tag", columns: ["name"])
            try db.alter(table: "root") { table in
                table.add(column: "tagsReadAt", .double)
            }
        }
        return migrator
    }

    // MARK: - Roots

    public func roots() throws -> [IndexRoot] {
        try writer.read { db in try Row.fetchAll(db, sql: "SELECT * FROM root ORDER BY path").map(Self.root) }
    }

    /// Adds a root (or updates its exclusions if it exists) and returns it.
    public func addRoot(path: String, exclusions: [String]) throws -> IndexRoot {
        let encoded = try String(data: JSONEncoder().encode(exclusions), encoding: .utf8) ?? "[]"
        return try writer.write { db in
            if let row = try Row.fetchOne(db, sql: "SELECT * FROM root WHERE path = ?", arguments: [path]) {
                try db.execute(sql: "UPDATE root SET exclusions = ? WHERE id = ?", arguments: [encoded, row["id"]])
                return try Self.root(Row.fetchOne(db, sql: "SELECT * FROM root WHERE path = ?", arguments: [path])!)
            }
            let name = (path as NSString).lastPathComponent
            try db.execute(
                sql: """
                INSERT INTO item (parent, rootID, name, kind, size, allocated, totalSize, totalAllocated, hidden, depth)
                VALUES (NULL, 0, ?, ?, 0, 0, 0, 0, 0, 0)
                """,
                arguments: [name.isEmpty ? path : name, Kind.directory.rawValue]
            )
            let itemID = db.lastInsertedRowID
            try db.execute(
                sql: "INSERT INTO root (path, itemID, exclusions) VALUES (?, ?, ?)",
                arguments: [path, itemID, encoded]
            )
            let rootID = db.lastInsertedRowID
            try db.execute(sql: "UPDATE item SET rootID = ? WHERE id = ?", arguments: [rootID, itemID])
            return try Self.root(Row.fetchOne(db, sql: "SELECT * FROM root WHERE id = ?", arguments: [rootID])!)
        }
    }

    public func setExclusions(_ id: Int64, _ exclusions: [String]) throws {
        let encoded = try String(data: JSONEncoder().encode(exclusions), encoding: .utf8) ?? "[]"
        try writer.write { db in
            try db.execute(sql: "UPDATE root SET exclusions = ? WHERE id = ?", arguments: [encoded, id])
        }
    }

    /// Items and total size indexed under a root.
    public func summary(of root: IndexRoot) throws -> (items: Int64, totalSize: Int64) {
        let item = try item(root.itemID)
        return (item?.descendants ?? 0, item?.totalSize ?? 0)
    }

    public func removeRoot(_ id: Int64) throws {
        try writer.write { db in
            let itemID = try Int64.fetchOne(db, sql: "SELECT itemID FROM root WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [itemID])
            try db.execute(sql: "DELETE FROM root WHERE id = ?", arguments: [id])
        }
    }

    /// The deepest root whose folder contains `path`.
    public func root(containing path: String) throws -> IndexRoot? {
        try roots()
            .filter { path == $0.path || path.hasPrefix($0.path == "/" ? "/" : $0.path + "/") }
            .max { $0.path.count < $1.path.count }
    }

    public func markScanned(_ id: Int64, eventID: UInt64, volumeUUID: String?) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE root SET scannedAt = ?, lastEventID = ?, volumeUUID = ? WHERE id = ?",
                arguments: [Date().timeIntervalSince1970, Int64(bitPattern: eventID), volumeUUID, id]
            )
        }
    }

    public func setLastEventID(_ id: Int64, _ eventID: UInt64) throws {
        try writer.write { db in
            try db.execute(
                sql: "UPDATE root SET lastEventID = ? WHERE id = ?", arguments: [Int64(bitPattern: eventID), id]
            )
        }
    }

    // MARK: - Items

    /// Resolves `path` component by component from its root.
    public func itemID(forPath path: String) throws -> Int64? {
        guard let root = try root(containing: path) else { return nil }
        let relative = path.dropFirst(root.path.count)
        let components = relative.split(separator: "/").map(String.init)
        return try writer.read { db in
            var current: Int64? = root.itemID
            for component in components {
                guard let parent = current else { return nil }
                current = try Int64.fetchOne(
                    db, sql: "SELECT id FROM item WHERE parent = ? AND name = ?", arguments: [parent, component]
                )
            }
            return current
        }
    }

    public func item(_ id: Int64) throws -> IndexedItem? {
        try writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM item WHERE id = ?", arguments: [id]).map(Self.item)
        }
    }

    public func children(of id: Int64) throws -> [IndexedItem] {
        try writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM item WHERE parent = ? ORDER BY name", arguments: [id])
                .map(Self.item)
        }
    }

    /// Total sizes of the items in the folder at `path`, by name. Empty if not indexed.
    public func childSizes(ofFolder path: String) throws -> [String: Int64] {
        guard let id = try itemID(forPath: path) else { return [:] }
        return try writer.read { db in
            var sizes: [String: Int64] = [:]
            let rows = try Row.fetchCursor(
                db,
                sql: "SELECT name, totalSize FROM item WHERE parent = ?",
                arguments: [id]
            )
            while let row = try rows.next() {
                sizes[row["name"]] = row["totalSize"]
            }
            return sizes
        }
    }

    public func itemCount() throws -> Int {
        try writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item") ?? 0 }
    }

    /// Deletes an item and everything below it.
    public func deleteItem(_ id: Int64) throws {
        try writer.write { db in try db.execute(sql: "DELETE FROM item WHERE id = ?", arguments: [id]) }
    }

    /// Inserts directory entries under `parent` and returns their IDs, in order.
    func insertChildren(_ entries: [DirectoryEntry], parent: Int64, rootID: Int64, depth: Int) throws -> [Int64] {
        try writer.write { db in try Self.insert(entries, parent: parent, rootID: rootID, depth: depth, db) }
    }

    static func insert(
        _ entries: [DirectoryEntry], parent: Int64, rootID: Int64, depth: Int, _ db: Database
    ) throws -> [Int64] {
        let statement = try db.cachedStatement(sql: """
        INSERT INTO item (parent, rootID, name, kind, fileID, size, allocated, totalSize, totalAllocated,
                          created, modified, hidden, depth)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """)
        return try entries.map { entry in
            try statement.execute(arguments: [
                parent, rootID, entry.name, Kind(entry.kind).rawValue, Int64(bitPattern: entry.fileID),
                entry.size, entry.allocatedSize, entry.size, entry.allocatedSize,
                entry.created.timeIntervalSince1970, entry.modified.timeIntervalSince1970, entry.isHidden, depth,
            ])
            return db.lastInsertedRowID
        }
    }

    // MARK: - Rows

    enum Kind: Int {
        case file = 0, directory = 1, symlink = 2, other = 3

        init(_ kind: DirectoryEntry.Kind) {
            self = switch kind {
            case .file: .file
            case .directory: .directory
            case .symlink: .symlink
            case .other: .other
            }
        }
    }

    private static func root(_ row: Row) throws -> IndexRoot {
        let exclusions = try JSONDecoder().decode([String].self, from: Data((row["exclusions"] as String).utf8))
        let eventID: Int64? = row["lastEventID"]
        let scannedAt: Double? = row["scannedAt"]
        let tagsReadAt: Double? = row["tagsReadAt"]
        return IndexRoot(
            id: row["id"], path: row["path"], itemID: row["itemID"], exclusions: exclusions,
            volumeUUID: row["volumeUUID"], lastEventID: eventID.map { UInt64(bitPattern: $0) },
            scannedAt: scannedAt.map(Date.init(timeIntervalSince1970:)),
            tagsReadAt: tagsReadAt.map(Date.init(timeIntervalSince1970:))
        )
    }

    private static func item(_ row: Row) -> IndexedItem {
        IndexedItem(
            id: row["id"], parent: row["parent"], name: row["name"],
            isDirectory: row["kind"] == Kind.directory.rawValue,
            size: row["size"], totalSize: row["totalSize"], totalAllocated: row["totalAllocated"],
            descendants: row["descendants"], modified: Date(timeIntervalSince1970: row["modified"] ?? 0)
        )
    }
}
