import CanvasKit
import Foundation
import GRDB

struct Workspace: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "workspace"

    var id: Int64
    var name: String
    var position: Int
    /// The saved canvas (`CanvasSnapshot` as JSON), if the workspace was ever used.
    var canvas: Data?
}

struct Favorite: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "favorite"

    var id: Int64
    var path: String
    var colorIndex: Int
    var position: Int

    var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}

/// The app's own data: workspaces (each with its canvas), favorites and settings, in SQLite.
final class AppDatabase: Sendable {
    let writer: any DatabaseWriter

    private init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try AppDatabase(DatabaseQueue(path: url.path))
    }

    /// `~/Library/Application Support/Arbor/arbor.sqlite`.
    static func openDefault() throws -> AppDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return try open(at: support.appendingPathComponent("Arbor/arbor.sqlite"))
    }

    static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "workspace") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("name", .text).notNull()
                table.column("position", .integer).notNull()
                table.column("canvas", .blob)
            }
            try db.create(table: "favorite") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("path", .text).notNull().unique()
                table.column("colorIndex", .integer).notNull()
                table.column("position", .integer).notNull()
            }
            try db.create(table: "setting") { table in
                table.primaryKey("key", .text)
                table.column("value", .text)
            }
        }
        migrator.registerMigration("v2-shares") { db in
            try db.create(table: "share") { table in
                table.primaryKey("url", .text)
                table.column("name", .text).notNull()
            }
        }
        return migrator
    }

    /// On first launch: one workspace (current) and the given favorites.
    func seedIfEmpty(defaultWorkspaceName: String, favorites: [URL]) throws {
        try writer.write { db in
            guard try Workspace.fetchCount(db) == 0 else { return }
            let id = try Self.insertWorkspace(name: defaultWorkspaceName, db)
            try Self.setSetting("currentWorkspace", "\(id)", db)
            for url in favorites {
                _ = try Self.insertFavorite(url, colorIndex: nil, db)
            }
        }
    }

    // MARK: - Workspaces

    func workspaces() throws -> [Workspace] {
        try writer.read { db in try Workspace.order(Column("position")).fetchAll(db) }
    }

    @discardableResult
    func createWorkspace(name: String) throws -> Workspace {
        try writer.write { db in
            let id = try Self.insertWorkspace(name: name, db)
            return try Workspace.fetchOne(db, key: id)!
        }
    }

    func renameWorkspace(_ id: Int64, to name: String) throws {
        try writer.write { db in
            _ = try Workspace.filter(key: id).updateAll(db, Column("name").set(to: name))
        }
    }

    /// Deletes a workspace; if it was current, the first remaining one becomes current.
    func deleteWorkspace(_ id: Int64) throws {
        try writer.write { db in
            _ = try Workspace.deleteOne(db, key: id)
            if try Self.setting("currentWorkspace", db) == "\(id)" {
                let next = try Workspace.order(Column("position")).fetchOne(db)
                try Self.setSetting("currentWorkspace", next.map { "\($0.id)" }, db)
            }
        }
    }

    func saveCanvas(_ canvas: Data, for id: Int64) throws {
        try writer.write { db in
            _ = try Workspace.filter(key: id).updateAll(db, Column("canvas").set(to: canvas))
        }
    }

    func canvas(for id: Int64) throws -> Data? {
        try writer.read { db in try Workspace.fetchOne(db, key: id)?.canvas }
    }

    func currentWorkspaceID() throws -> Int64? {
        try writer.read { db in try Self.setting("currentWorkspace", db).flatMap(Int64.init) }
    }

    func setCurrentWorkspace(_ id: Int64) throws {
        try writer.write { db in try Self.setSetting("currentWorkspace", "\(id)", db) }
    }

    // MARK: - Favorites

    func favorites() throws -> [Favorite] {
        try writer.read { db in try Favorite.order(Column("position")).fetchAll(db) }
    }

    /// Adds a favorite at the end, in `colorIndex` or the least used color. Returns nil if
    /// the folder already is a favorite.
    @discardableResult
    func addFavorite(_ url: URL, colorIndex: Int?) throws -> Favorite? {
        try writer.write { db in try Self.insertFavorite(url, colorIndex: colorIndex, db) }
    }

    func removeFavorite(_ id: Int64) throws {
        try writer.write { db in _ = try Favorite.deleteOne(db, key: id) }
    }

    func setFavoriteColor(_ id: Int64, to colorIndex: Int) throws {
        try writer.write { db in
            _ = try Favorite.filter(key: id).updateAll(db, Column("colorIndex").set(to: colorIndex))
        }
    }

    /// Moves a favorite to `index` in the list, shifting the others.
    func moveFavorite(_ id: Int64, to index: Int) throws {
        try writer.write { db in
            var ordered = try Favorite.order(Column("position")).fetchAll(db)
            guard let from = ordered.firstIndex(where: { $0.id == id }) else { return }
            let moved = ordered.remove(at: from)
            ordered.insert(moved, at: min(max(index, 0), ordered.count))
            for (position, favorite) in ordered.enumerated() {
                _ = try Favorite.filter(key: favorite.id).updateAll(db, Column("position").set(to: position))
            }
        }
    }

    // MARK: - Helpers

    private static func insertWorkspace(name: String, _ db: Database) throws -> Int64 {
        let position = try (Int.fetchOne(db, sql: "SELECT MAX(position) FROM workspace") ?? -1) + 1
        try db.execute(
            sql: "INSERT INTO workspace (name, position) VALUES (?, ?)", arguments: [name, position]
        )
        return db.lastInsertedRowID
    }

    private static func insertFavorite(_ url: URL, colorIndex: Int?, _ db: Database) throws -> Favorite? {
        guard try Favorite.filter(Column("path") == url.path).fetchCount(db) == 0 else { return nil }
        let used = try Int.fetchAll(db, sql: "SELECT colorIndex FROM favorite")
        let position = try (Int.fetchOne(db, sql: "SELECT MAX(position) FROM favorite") ?? -1) + 1
        try db.execute(
            sql: "INSERT INTO favorite (path, colorIndex, position) VALUES (?, ?, ?)",
            arguments: [url.path, colorIndex ?? BranchPalette.nextIndex(used: used), position]
        )
        return try Favorite.fetchOne(db, key: db.lastInsertedRowID)
    }

    private static func setting(_ key: String, _ db: Database) throws -> String? {
        try String.fetchOne(db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [key])
    }

    private static func setSetting(_ key: String, _ value: String?, _ db: Database) throws {
        try db.execute(
            sql: "INSERT INTO setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
            arguments: [key, value]
        )
    }
}
