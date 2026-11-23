@testable import IndexKit
import XCTest

/// Root/{notes/meeting.md, code/main.swift, photo.jpg, answers.txt (empty)}
final class IndexContentTests: XCTestCase {
    private var temp: TemporaryDirectory!
    private var store: IndexStore!
    private var root: IndexRoot!

    override func setUpWithError() throws {
        temp = try TemporaryDirectory()
        try write("Budget meeting in Zanzibar", to: "notes/meeting.md")
        try write("let answer = 42", to: "code/main.swift")
        try write("Zanzibar", to: "photo.jpg")
        try temp.file("answers.txt")
        store = try IndexStore.inMemory()
        root = try store.addRoot(path: temp.url.path, exclusions: [])
        try IndexScanner(store: store).scan(root)
    }

    override func tearDown() {
        temp.remove()
    }

    private func write(_ text: String, to path: String) throws {
        let url = try temp.file(path)
        try Data(text.utf8).write(to: url)
    }

    private func contents() throws -> [String] {
        try store.writer.read { db in try String.fetchAll(db, sql: "SELECT text FROM item_content ORDER BY text") }
    }

    private func unread() throws -> Int {
        try store.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM item WHERE contentRead = 0") }
            ?? -1
    }

    func testReadsDocumentsOnceAndSkipsOtherFiles() throws {
        XCTAssertEqual(try store.readContents(), 2)
        XCTAssertEqual(try contents(), ["Budget meeting in Zanzibar", "let answer = 42"])
        XCTAssertEqual(try unread(), 0, "folders and other files are marked read too")
        XCTAssertEqual(try store.readContents(), 0, "nothing left to read")
    }

    func testChangedFilesAreReadAgainAndDeletedOnesDropped() throws {
        try store.readContents()
        try write("Budget meeting moved to Madagascar", to: "notes/meeting.md")
        try FileManager.default.removeItem(at: temp.url.appendingPathComponent("code"))
        try IndexUpdater(store: store).apply([
            FolderChange(path: temp.url.appendingPathComponent("notes").path, mustRescanSubfolders: false, eventID: 1),
            FolderChange(path: temp.url.path, mustRescanSubfolders: false, eventID: 2),
        ])
        XCTAssertEqual(try store.readContents(), 1)
        XCTAssertEqual(try contents(), ["Budget meeting moved to Madagascar"])
    }

    func testSearchFindsWordsInDocumentsAfterNameMatches() throws {
        try store.readContents()
        let found = try store.search(SearchQuery(text: "zanz"))
        XCTAssertEqual(found.map(\.name), ["meeting.md"], "images are not read")
        XCTAssertEqual(found.first?.excerpt, "Budget meeting in Zanzibar")
        XCTAssertEqual(try store.search(SearchQuery(text: "answer")).map(\.name), ["answers.txt", "main.swift"])
        XCTAssertNil(try store.search(SearchQuery(text: "answer")).first?.excerpt)
        XCTAssertEqual(
            try store.search(SearchQuery(text: "zanzibar", category: .code)).map(\.name), [],
            "filters apply to text matches"
        )
    }

    func testCancellationStopsThePass() throws {
        let control = ScanControl()
        control.cancel()
        XCTAssertThrowsError(try store.readContents(control: control))
    }
}
