import Foundation
import GRDB

/// A network share Arbor remembers, to reconnect it in one click.
struct RememberedShare: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "share"

    /// The share's URL (`smb://server/share`), without a password.
    var url: URL
    var name: String
}

extension AppDatabase {
    /// Remembered shares, by name.
    func shares() throws -> [RememberedShare] {
        try writer
            .read { db in try RememberedShare.order(Column("name").collating(.localizedStandardCompare)).fetchAll(db) }
    }

    /// Remembers a share, or updates its name.
    func rememberShare(_ url: URL, name: String) throws {
        try writer.write { db in try RememberedShare(url: url, name: name).upsert(db) }
    }

    func forgetShare(_ url: URL) throws {
        try writer.write { db in _ = try RememberedShare.deleteOne(db, key: url) }
    }
}
