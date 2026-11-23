import Foundation
import PDFKit
import ZIPFoundation

/// Plain text of documents, for content search: PDF, Word / Excel / PowerPoint (Office Open
/// XML), plain text, Markdown and code.
public enum TextExtractor {
    // ponytail: only the start of each file is searchable; raise if people search deep into books.
    /// Characters kept per file.
    public static let maxCharacters = 100_000
    /// Larger archive members are skipped (a zip bomb would otherwise fill memory).
    static let maxMemberSize = 50_000_000

    static let plainExtensions = Set(["txt", "text", "md", "markdown", "csv", "tsv", "log", "tex"])
        .union(FileCategory.code.extensions)

    /// The archive members holding an Office document's text, in reading order.
    private static let officeMembers: [String: @Sendable (String) -> Bool] = [
        "docx": { $0 == "word/document.xml" },
        "xlsx": { $0 == "xl/sharedStrings.xml" },
        "pptx": { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") },
    ]

    public static func canExtract(name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ext == "pdf" || officeMembers[ext] != nil || plainExtensions.contains(ext)
    }

    /// The file's text with runs of white space collapsed, or nil when it has none or cannot
    /// be read.
    public static func text(atPath path: String) -> String? {
        let ext = (path as NSString).pathExtension.lowercased()
        let raw: String? = if ext == "pdf" {
            pdfText(path)
        } else if let isMember = officeMembers[ext] {
            officeText(path, isMember)
        } else if plainExtensions.contains(ext) {
            plainText(path)
        } else {
            nil
        }
        let text = raw?.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(maxCharacters)
        return text.flatMap { $0.isEmpty ? nil : String($0) }
    }

    private static func plainText(_ path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        let limit = maxCharacters * 4
        guard let data = try? handle.read(upToCount: limit), !data.contains(0) else { return nil }
        // UTF-8, possibly cut inside a character at the read limit; else Latin-1, which always decodes.
        let cuts = data.count == limit ? 0 ... 3 : 0 ... 0
        return cuts.lazy.compactMap { String(bytes: data.dropLast($0), encoding: .utf8) }.first
            ?? String(bytes: data, encoding: .isoLatin1)
    }

    private static func pdfText(_ path: String) -> String? {
        guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else { return nil }
        var text = ""
        for index in 0 ..< document.pageCount where text.utf16.count < maxCharacters {
            text += (document.page(at: index)?.string ?? "") + "\n"
        }
        return text
    }

    private static func officeText(_ path: String, _ isMember: @Sendable (String) -> Bool) -> String? {
        guard let archive = try? Archive(url: URL(fileURLWithPath: path), accessMode: .read) else { return nil }
        let members = archive.filter { isMember($0.path) && $0.uncompressedSize <= maxMemberSize }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        var text = ""
        for member in members where text.utf16.count < maxCharacters {
            var data = Data()
            guard (try? archive.extract(member) { data.append($0) }) != nil else { continue }
            text += XMLText.text(of: data) + "\n"
        }
        return text
    }
}

/// The character data of an XML document, with a space after each paragraph, row or break.
private final class XMLText: NSObject, XMLParserDelegate {
    private var text = ""
    private static let breaks: Set<String> = ["p", "si", "br", "tab", "row", "c"]

    static func text(of data: Data) -> String {
        let collector = XMLText()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        return collector.text
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
        if Self.breaks.contains(String(name.split(separator: ":").last ?? "")) {
            text += " "
        }
    }
}
