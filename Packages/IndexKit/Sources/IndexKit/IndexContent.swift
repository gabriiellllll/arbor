import Foundation
import GRDB

extension IndexStore {
    /// Larger files are not read for content search.
    static let maxContentFileSize: Int64 = 100_000_000

    /// Reads the text of the documents that changed since they were last read, in small
    /// batches (extraction runs outside database transactions), until none is left. Returns
    /// how many documents got text.
    @discardableResult
    public func readContents(control: ScanControl = ScanControl()) throws -> Int {
        let roots = try Dictionary(uniqueKeysWithValues: roots().map { ($0.id, $0.path) })
        var read = 0
        while true {
            if control.isCancelled {
                throw CancellationError()
            }
            let batch = try writer.read { db in try Self.unreadBatch(roots, db) }
            if batch.isEmpty {
                return read
            }
            let texts = batch.map { item in
                item.path.flatMap { path in autoreleasepool { TextExtractor.text(atPath: path) } }
            }
            read += try writer.write { db in
                var stored = 0
                for (item, text) in zip(batch, texts) {
                    // A change since the batch was fetched leaves the item unread, for the next batch.
                    try db.execute(
                        sql: "UPDATE item SET contentRead = 1 WHERE id = ? AND modified IS ? AND size = ?",
                        arguments: [item.id, item.modified, item.size]
                    )
                    guard db.changesCount > 0 else { continue }
                    try db.execute(sql: "DELETE FROM item_content WHERE rowid = ?", arguments: [item.id])
                    if let text {
                        try db.execute(
                            sql: "INSERT INTO item_content (rowid, text) VALUES (?, ?)", arguments: [item.id, text]
                        )
                        stored += 1
                    }
                }
                return stored
            }
        }
    }

    private struct UnreadItem {
        let id: Int64
        let modified: Double?
        let size: Int64
        /// Set for documents worth reading.
        let path: String?
    }

    private static func unreadBatch(_ roots: [Int64: String], _ db: Database) throws -> [UnreadItem] {
        try Row.fetchAll(
            db, sql: "SELECT id, rootID, name, kind, size, modified FROM item WHERE contentRead = 0 LIMIT 100"
        ).map { row -> UnreadItem in
            let id: Int64 = row["id"]
            let size: Int64 = row["size"]
            let wanted = row["kind"] == Kind.file.rawValue && size <= maxContentFileSize
                && TextExtractor.canExtract(name: row["name"])
            let rootID: Int64 = row["rootID"]
            let rootPath = roots[rootID]
            let itemPath: String? = if wanted, let rootPath {
                try Self.path(of: id, rootPath: rootPath, db)
            } else {
                nil
            }
            return UnreadItem(id: id, modified: row["modified"], size: size, path: itemPath)
        }
    }
}
