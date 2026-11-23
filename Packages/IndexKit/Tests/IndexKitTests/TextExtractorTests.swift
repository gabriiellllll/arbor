import CoreText
@testable import IndexKit
import XCTest
import ZIPFoundation

final class TextExtractorTests: XCTestCase {
    private var temp: TemporaryDirectory!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
    }

    override func tearDown() {
        temp.remove()
    }

    private func write(_ text: String, to name: String) throws -> String {
        let url = temp.url.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url.path
    }

    /// An Office Open XML file: a zip of XML members.
    private func office(_ name: String, _ members: [String: String]) throws -> String {
        let url = temp.url.appendingPathComponent(name)
        let archive = try Archive(url: url, accessMode: .create)
        for (path, xml) in members {
            let data = Data(xml.utf8)
            try archive.addEntry(
                with: path, type: .file, uncompressedSize: Int64(data.count), compressionMethod: .deflate
            ) { position, size in data.subdata(in: Int(position) ..< Int(position) + size) }
        }
        return url.path
    }

    func testPlainTextAndCodeCollapseWhiteSpace() throws {
        XCTAssertEqual(try TextExtractor.text(atPath: write("Hello\n\n  wörld\t!", to: "a.md")), "Hello wörld !")
        XCTAssertEqual(try TextExtractor.text(atPath: write("let x = 1", to: "main.swift")), "let x = 1")
        XCTAssertNil(try TextExtractor.text(atPath: write("  \n", to: "empty.txt")), "no text, nothing stored")
        let latin1 = temp.url.appendingPathComponent("old.txt")
        try XCTUnwrap("Café".data(using: .isoLatin1)).write(to: latin1)
        XCTAssertEqual(TextExtractor.text(atPath: latin1.path), "Café")
    }

    func testBinaryAndUnknownFilesHaveNoText() throws {
        let binary = temp.url.appendingPathComponent("data.txt")
        try Data([0x41, 0x00, 0x42]).write(to: binary)
        XCTAssertNil(TextExtractor.text(atPath: binary.path))
        XCTAssertNil(try TextExtractor.text(atPath: write("text", to: "photo.jpg")))
        XCTAssertFalse(TextExtractor.canExtract(name: "photo.jpg"))
        XCTAssertTrue(TextExtractor.canExtract(name: "Report.DOCX"))
        XCTAssertTrue(TextExtractor.canExtract(name: "paper.pdf"))
    }

    func testTextIsCappedPerFile() throws {
        let long = String(repeating: "word ", count: TextExtractor.maxCharacters)
        XCTAssertEqual(try TextExtractor.text(atPath: write(long, to: "long.txt"))?.count, TextExtractor.maxCharacters)
    }

    func testWordDocument() throws {
        let path = try office("letter.docx", [
            "word/document.xml": """
            <w:document xmlns:w="w"><w:body><w:p><w:r><w:t>Dear </w:t></w:r><w:r><w:t>Zanzi</w:t></w:r>\
            <w:r><w:t>bar &amp; co</w:t></w:r></w:p><w:p><w:r><w:t>Regards</w:t></w:r></w:p></w:body></w:document>
            """,
            "word/styles.xml": "<w:styles xmlns:w=\"w\"><w:t>Ignored</w:t></w:styles>",
        ])
        XCTAssertEqual(TextExtractor.text(atPath: path), "Dear Zanzibar & co Regards")
    }

    func testSpreadsheetSharedStrings() throws {
        let path = try office("budget.xlsx", [
            "xl/sharedStrings.xml": "<sst><si><t>Revenue</t></si><si><r><t>Net </t></r><r><t>income</t></r></si></sst>",
        ])
        XCTAssertEqual(TextExtractor.text(atPath: path), "Revenue Net income")
    }

    func testPresentationSlidesInOrder() throws {
        let slide = { (text: String) in
            "<p:sld xmlns:p=\"p\" xmlns:a=\"a\"><a:p><a:r><a:t>\(text)</a:t></a:r></a:p></p:sld>"
        }
        let path = try office("deck.pptx", [
            "ppt/slides/slide10.xml": slide("Ten"),
            "ppt/slides/slide2.xml": slide("Two"),
            "ppt/slides/slide1.xml": slide("One"),
            "ppt/slides/_rels/slide1.xml.rels": "<r>Ignored</r>",
        ])
        XCTAssertEqual(TextExtractor.text(atPath: path), "One Two Ten")
    }

    func testPDF() throws {
        let url = temp.url.appendingPathComponent("paper.pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 200)
        let context = try XCTUnwrap(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: "Quarterly zanzibar figures", attributes: [.font: font])
        )
        context.textPosition = CGPoint(x: 20, y: 100)
        CTLineDraw(line, context)
        context.endPDFPage()
        context.closePDF()
        XCTAssertEqual(TextExtractor.text(atPath: url.path), "Quarterly zanzibar figures")
    }

    func testDamagedDocumentsHaveNoText() throws {
        XCTAssertNil(try TextExtractor.text(atPath: write("not a zip", to: "broken.docx")))
        XCTAssertNil(try TextExtractor.text(atPath: write("not a pdf", to: "broken.pdf")))
    }
}
