@testable import FileOpsKit
import XCTest

final class BatchRenameTests: XCTestCase {
    private func names(_ files: [String], _ rules: RenameRules) -> [String] {
        let subjects = files.map { RenameSubject(url: URL(fileURLWithPath: "/Photos/\($0)")) }
        return BatchRename.preview(subjects, rules: rules, exists: { _ in false }).rows.map(\.newName)
    }

    func testDefaultRulesKeepNames() {
        XCTAssertEqual(names(["a.jpg", "Folder"], RenameRules()), ["a.jpg", "Folder"])
    }

    func testFindReplaceIgnoresCaseUnlessAsked() {
        var rules = RenameRules()
        rules.find = "img"
        rules.replace = "Photo"
        XCTAssertEqual(names(["IMG_001.jpg", "img_002.jpg"], rules), ["Photo_001.jpg", "Photo_002.jpg"])
        rules.caseSensitive = true
        XCTAssertEqual(names(["IMG_001.jpg", "img_002.jpg"], rules), ["IMG_001.jpg", "Photo_002.jpg"])
    }

    func testRegexWithCaptureGroups() {
        var rules = RenameRules()
        rules.find = #"(\d{4})-(\d{2})"#
        rules.replace = "$2.$1"
        rules.usesRegex = true
        XCTAssertEqual(names(["report 2024-05.pdf"], rules), ["report 05.2024.pdf"])
    }

    func testInvalidRegexIsReported() {
        var rules = RenameRules()
        rules.find = "(unclosed"
        rules.usesRegex = true
        let preview = BatchRename.preview(
            [RenameSubject(url: URL(fileURLWithPath: "/a.txt"))], rules: rules, exists: { _ in false }
        )
        XCTAssertNotNil(preview.patternError)
        XCTAssertFalse(preview.canRename)
    }

    func testExtensionIsKeptUnlessIncluded() {
        var rules = RenameRules()
        rules.find = "jpg"
        rules.replace = "png"
        XCTAssertEqual(names(["jpg file.jpg"], rules), ["png file.jpg"])
        rules.includesExtension = true
        XCTAssertEqual(names(["jpg file.jpg"], rules), ["png file.png"])
    }

    func testTemplateAddsPrefixSuffixAndPaddedNumbers() {
        var rules = RenameRules()
        rules.template = "Trip {n:3} - {name} (final)"
        rules.startNumber = 9
        XCTAssertEqual(
            names(["beach.jpg", "hill.jpg"], rules),
            ["Trip 009 - beach (final).jpg", "Trip 010 - hill (final).jpg"]
        )
        rules.template = "{name}_{n}"
        rules.startNumber = 1
        XCTAssertEqual(names(["a.txt", "b.txt"], rules), ["a_1.txt", "b_2.txt"])
    }

    func testUnknownTokensStayAsText() {
        var rules = RenameRules()
        rules.template = "{name} {nope} {"
        XCTAssertEqual(names(["a.txt"], rules), ["a {nope} {.txt"])
    }

    func testCaseChangeAppliesToTheBaseName() {
        var rules = RenameRules()
        rules.caseChange = .upper
        XCTAssertEqual(names(["my photo.jpg"], rules), ["MY PHOTO.jpg"])
        rules.caseChange = .lower
        XCTAssertEqual(names(["My Photo.JPG"], rules), ["my photo.JPG"])
        rules.caseChange = .title
        XCTAssertEqual(names(["my BIG photo.jpg"], rules), ["My Big Photo.jpg"])
    }

    func testReplaceRunsBeforeTemplateThenCase() {
        var rules = RenameRules()
        rules.find = "draft"
        rules.replace = "final"
        rules.template = "{n:2} {name}"
        rules.caseChange = .upper
        XCTAssertEqual(names(["draft.md"], rules), ["01 FINAL.md"])
    }

    // MARK: - Collisions

    private func problems(
        _ paths: [String], _ rules: RenameRules, existing: Set<String> = []
    ) -> [RenamePreview.Problem?] {
        let subjects = paths.map { RenameSubject(url: URL(fileURLWithPath: $0)) }
        let all = existing.union(paths)
        return BatchRename.preview(subjects, rules: rules, exists: { all.contains($0.path) }).rows.map(\.problem)
    }

    func testSameNewNameInOneFolderIsADuplicate() {
        var rules = RenameRules()
        rules.template = "photo"
        XCTAssertEqual(problems(["/A/x.jpg", "/A/y.jpg", "/B/z.jpg"], rules), [.duplicate, .duplicate, nil])
    }

    func testDuplicatesIgnoreCase() {
        var rules = RenameRules()
        rules.find = "x"
        rules.replace = "Y"
        XCTAssertEqual(problems(["/A/x.txt", "/A/y.txt"], rules), [.duplicate, .duplicate])
    }

    func testNameOfAnItemOutsideTheBatchIsTaken() {
        var rules = RenameRules()
        rules.template = "{name} copy"
        XCTAssertEqual(problems(["/A/x.txt"], rules, existing: ["/A/x copy.txt"]), [.taken])
    }

    func testSwapsAndCaseOnlyChangesAreAllowed() {
        var rules = RenameRules()
        rules.template = "{name}a"
        // a → aa while aa → aaa: aa is in the batch, so it moves out of the way.
        XCTAssertEqual(problems(["/A/a", "/A/aa"], rules), [nil, nil])
        var upper = RenameRules()
        upper.caseChange = .upper
        let preview = BatchRename.preview(
            [RenameSubject(url: URL(fileURLWithPath: "/A/a.txt"))], rules: upper,
            exists: { $0.path.lowercased() == "/a/a.txt" }
        )
        XCTAssertEqual(preview.rows.map(\.newName), ["A.txt"])
        XCTAssertEqual(preview.rows.map(\.problem), [nil])
        XCTAssertTrue(preview.canRename)
    }

    func testInvalidNames() {
        var rules = RenameRules()
        rules.includesExtension = true
        for template in ["", ".", "..", "a/b", "a:b"] {
            rules.template = template
            XCTAssertEqual(problems(["/A/x.txt"], rules), [.invalidName], template)
        }
    }

    func testNothingToDoMeansNothingToRename() {
        let preview = BatchRename.preview(
            [RenameSubject(url: URL(fileURLWithPath: "/A/x.txt"))], rules: RenameRules(), exists: { _ in true }
        )
        XCTAssertEqual(preview.rows.map(\.problem), [nil])
        XCTAssertFalse(preview.canRename)
    }
}
