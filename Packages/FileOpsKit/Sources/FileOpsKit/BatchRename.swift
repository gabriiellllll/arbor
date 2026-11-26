import Foundation

/// How to rename a batch of items. Applied in order: find/replace, then the template, then
/// the case change. The extension is kept apart unless `includesExtension`.
public struct RenameRules: Equatable, Sendable {
    public enum CaseChange: String, CaseIterable, Sendable {
        case none, lower, upper, title
    }

    public var find = ""
    public var replace = ""
    public var usesRegex = false
    public var caseSensitive = false
    /// The new name. Tokens: `{name}` (after find/replace), `{n}` or `{n:3}` (numbered from
    /// `startNumber`, zero-padded), `{created:yyyy-MM-dd}`, `{modified:…}`, `{exif:…}` (the
    /// date a photo was taken). Anything else is kept as text.
    public var template = "{name}"
    public var startNumber = 1
    public var caseChange = CaseChange.none
    public var includesExtension = false

    public init() {}
}

/// An item to rename, with the dates templates can use.
public struct RenameSubject: Equatable, Sendable {
    public let url: URL
    public var created: Date?
    public var modified: Date?
    /// When the photo was taken (EXIF), if the item is a photo that says so.
    public var photoTaken: Date?

    public init(url: URL, created: Date? = nil, modified: Date? = nil, photoTaken: Date? = nil) {
        self.url = url
        self.created = created
        self.modified = modified
        self.photoTaken = photoTaken
    }
}

/// The names a batch rename would give, and what prevents it.
public struct RenamePreview: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// Empty, `.`/`..`, or containing `/` or `:`.
        case invalidName
        /// Another item of the batch gets the same name in the same folder.
        case duplicate
        /// An item that is not renamed already has this name.
        case taken
        /// The template uses the photo date and the item has none.
        case noPhotoDate
    }

    public struct Row: Equatable, Sendable {
        public let source: URL
        public let newName: String
        public var problem: Problem?

        public var changes: Bool {
            newName != source.lastPathComponent
        }
    }

    public var rows: [Row]
    /// Set when the find pattern is not a valid regular expression.
    public var patternError: String?

    /// Something changes and nothing is in the way.
    public var canRename: Bool {
        patternError == nil && rows.contains(where: \.changes) && rows.allSatisfy { $0.problem == nil }
    }
}

public enum BatchRename {
    /// The new name of each subject, in order. `exists` tells whether an item is at a URL.
    public static func preview(
        _ subjects: [RenameSubject], rules: RenameRules,
        exists _: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> RenamePreview {
        var regex: NSRegularExpression?
        if rules.usesRegex, !rules.find.isEmpty {
            do {
                regex = try NSRegularExpression(
                    pattern: rules.find, options: rules.caseSensitive ? [] : .caseInsensitive
                )
            } catch {
                return RenamePreview(
                    rows: subjects.map { .init(source: $0.url, newName: $0.url.lastPathComponent) },
                    patternError: error.localizedDescription
                )
            }
        }
        let rows = subjects.enumerated().map { index, subject in
            var missingDate = false
            let name = newName(
                of: subject, number: rules.startNumber + index, rules: rules, regex: regex,
                missingDate: &missingDate
            )
            return RenamePreview.Row(source: subject.url, newName: name, problem: missingDate ? .noPhotoDate : nil)
        }
        return RenamePreview(rows: rows)
    }

    static func newName(
        of subject: RenameSubject, number: Int, rules: RenameRules, regex: NSRegularExpression?,
        missingDate: inout Bool
    ) -> String {
        let fullName = subject.url.lastPathComponent
        let ext = rules.includesExtension ? "" : subject.url.pathExtension
        var base = ext.isEmpty ? fullName : String(fullName.dropLast(ext.count + 1))
        if let regex {
            base = regex.stringByReplacingMatches(
                in: base, range: NSRange(base.startIndex..., in: base), withTemplate: rules.replace
            )
        } else if !rules.find.isEmpty {
            base = base.replacingOccurrences(
                of: rules.find, with: rules.replace, options: rules.caseSensitive ? [] : .caseInsensitive
            )
        }
        base = expand(rules.template, name: base, number: number, subject: subject, missingDate: &missingDate)
        switch rules.caseChange {
        case .none: break
        case .lower: base = base.lowercased()
        case .upper: base = base.uppercased()
        case .title: base = base.capitalized
        }
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// Replaces the template's tokens.
    static func expand(
        _ template: String, name: String, number: Int, subject: RenameSubject, missingDate: inout Bool
    ) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            let token = rest[rest.index(after: open) ..< close]
            let parts = token.split(separator: ":", maxSplits: 1).map(String.init)
            let argument = parts.count > 1 ? parts[1] : nil
            switch parts.first {
            case "name":
                result += name
            case "n":
                let digits = String(number)
                let width = argument.flatMap(Int.init) ?? 0
                result += String(repeating: "0", count: max(0, width - digits.count)) + digits
            case "created", "modified", "exif":
                let date = parts[0] == "created" ? subject.created
                    : parts[0] == "modified" ? subject.modified : subject.photoTaken
                if let date {
                    result += format(date, argument ?? "yyyy-MM-dd")
                } else {
                    missingDate = true
                }
            default:
                result += rest[open ... close]
            }
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
