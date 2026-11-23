import Foundation
import GRDB

/// Kinds of files, by extension, for search filters.
public enum FileCategory: String, CaseIterable, Codable, Sendable {
    case images, documents, audio, video, archives, code

    public var extensions: [String] {
        switch self {
        case .images:
            [
                "jpg",
                "jpeg",
                "png",
                "heic",
                "heif",
                "gif",
                "tif",
                "tiff",
                "bmp",
                "webp",
                "svg",
                "psd",
                "raw",
                "dng",
                "cr2",
                "nef",
            ]
        case .documents:
            ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "txt", "md", "rtf",
             "odt", "ods", "odp", "csv"]
        case .audio:
            ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "ogg", "opus"]
        case .video:
            ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
        case .archives:
            ["zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "iso"]
        case .code:
            ["swift", "m", "h", "c", "cpp", "hpp", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt",
             "json", "yml", "yaml", "xml", "html", "css", "sh"]
        }
    }
}

/// A search of the index: words in names or document text, and filters. Filters alone also
/// search.
public struct SearchQuery: Equatable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case files, folders
    }

    public var text: String
    public var kind: Kind?
    public var category: FileCategory?
    public var minSize: Int64?
    public var maxSize: Int64?
    public var modifiedAfter: Date?
    public var modifiedBefore: Date?
    public var tag: String?
    public var rootID: Int64?
    public var limit: Int

    public init(
        text: String = "", kind: Kind? = nil, category: FileCategory? = nil, minSize: Int64? = nil,
        maxSize: Int64? = nil, modifiedAfter: Date? = nil, modifiedBefore: Date? = nil, tag: String? = nil,
        rootID: Int64? = nil, limit: Int = 500
    ) {
        self.text = text
        self.kind = kind
        self.category = category
        self.minSize = minSize
        self.maxSize = maxSize
        self.modifiedAfter = modifiedAfter
        self.modifiedBefore = modifiedBefore
        self.tag = tag
        self.rootID = rootID
        self.limit = limit
    }

    /// Nothing to search for.
    public var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty && kind == nil && category == nil && minSize == nil
            && maxSize == nil && modifiedAfter == nil && modifiedBefore == nil && tag == nil
    }

    /// Each word becomes a quoted prefix (`"rep"*`), all required: the user's text never
    /// reaches FTS5 as syntax.
    var matchExpression: String? {
        let words = text.split(whereSeparator: \.isWhitespace).map {
            "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*"
        }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }
}

public struct SearchResult: Equatable, Sendable {
    public let id: Int64
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let totalSize: Int64
    public let modified: Date
    /// Where the words appear in the document's text, when they do.
    public var excerpt: String?
}

extension IndexStore {
    public func search(_ query: SearchQuery) throws -> [SearchResult] {
        guard !query.isEmpty else { return [] }
        let roots = try Dictionary(uniqueKeysWithValues: roots().map { ($0.id, $0.path) })
        return try writer.read { db in
            var sql = "SELECT item.id, item.rootID, item.name, item.kind, item.totalSize, item.modified"
            var arguments: [any DatabaseValueConvertible] = []
            var conditions = ["item.parent IS NOT NULL"]
            let match = query.matchExpression
            if let match {
                // Name matches first, then matches in document text.
                sql += ", item.id IN (SELECT rowid FROM item_name WHERE item_name MATCH ?) AS byName"
                conditions.append("""
                item.id IN (SELECT rowid FROM item_name WHERE item_name MATCH ?
                            UNION SELECT rowid FROM item_content WHERE item_content MATCH ?)
                """)
                arguments += [match, match, match]
            }
            sql += " FROM item"
            if let tag = query.tag {
                sql += " JOIN tag ON tag.itemID = item.id AND tag.name = ?"
                arguments.insert(tag, at: match == nil ? 0 : 1)
            }
            Self.addFilters(query, to: &conditions, &arguments)
            sql += " WHERE " + conditions.joined(separator: " AND ")
            sql += match != nil ? " ORDER BY byName DESC, item.name" : " ORDER BY item.name"
            sql += " LIMIT ?"
            arguments.append(query.limit)
            var results = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                .compactMap { row -> SearchResult? in
                    let id: Int64 = row["id"]
                    guard let rootPath = roots[row["rootID"]],
                          let path = try Self.path(of: id, rootPath: rootPath, db)
                    else {
                        return nil
                    }
                    return SearchResult(
                        id: id, name: row["name"], path: path, isDirectory: row["kind"] == Kind.directory.rawValue,
                        totalSize: row["totalSize"], modified: Date(timeIntervalSince1970: row["modified"] ?? 0)
                    )
                }
            if let match {
                try Self.addExcerpts(match, to: &results, db)
            }
            return results
        }
    }

    private static func addExcerpts(_ match: String, to results: inout [SearchResult], _ db: Database) throws {
        guard !results.isEmpty else { return }
        let ids = results.map(\.id)
        let excerpts = try Dictionary(uniqueKeysWithValues: Row.fetchAll(db, sql: """
        SELECT rowid, snippet(item_content, 0, '', '', '…', 12) AS excerpt FROM item_content
        WHERE item_content MATCH ? AND rowid IN (\(ids.map { _ in "?" }.joined(separator: ",")))
        """, arguments: StatementArguments([match] + ids)).map { row -> (Int64, String) in
            (row["rowid"], row["excerpt"])
        })
        for index in results.indices {
            results[index].excerpt = excerpts[results[index].id]
        }
    }

    private static func addFilters(
        _ query: SearchQuery, to conditions: inout [String], _ arguments: inout [any DatabaseValueConvertible]
    ) {
        if let kind = query.kind {
            conditions.append(kind == .folders ? "item.kind = ?" : "item.kind != ?")
            arguments.append(Kind.directory.rawValue)
        }
        if let category = query.category {
            conditions.append("(" + category.extensions.map { _ in "item.name LIKE ?" }.joined(separator: " OR ") + ")")
            arguments += category.extensions.map { "%." + $0 }
        }
        let ranges: [(String, (any DatabaseValueConvertible)?)] = [
            ("item.totalSize >= ?", query.minSize),
            ("item.totalSize <= ?", query.maxSize),
            ("item.modified >= ?", query.modifiedAfter?.timeIntervalSince1970),
            ("item.modified <= ?", query.modifiedBefore?.timeIntervalSince1970),
            ("item.rootID = ?", query.rootID),
        ]
        for case let (condition, value?) in ranges {
            conditions.append(condition)
            arguments.append(value)
        }
    }

    /// The full path of an item: its root's path, then the names below it.
    static func path(of id: Int64, rootPath: String, _ db: Database) throws -> String? {
        let names = try String.fetchAll(db, sql: """
        WITH RECURSIVE chain(id, parent, name, depth) AS (
            SELECT id, parent, name, 0 FROM item WHERE id = ?
            UNION ALL
            SELECT item.id, item.parent, item.name, chain.depth + 1 FROM item JOIN chain ON item.id = chain.parent
        )
        SELECT name FROM chain WHERE parent IS NOT NULL ORDER BY depth DESC
        """, arguments: [id])
        guard !names.isEmpty else { return nil }
        return (rootPath as NSString).appendingPathComponent(names.joined(separator: "/"))
    }
}
