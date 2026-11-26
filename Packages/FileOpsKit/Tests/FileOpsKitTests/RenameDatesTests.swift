@testable import FileOpsKit
import ImageIO
import UniformTypeIdentifiers
import XCTest

final class RenameDatesTests: XCTestCase {
    private func date(_ text: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.date(from: text)!
    }

    func testDateTokensUseTheirFormat() {
        var rules = RenameRules()
        rules.template = "{exif:yyyy-MM-dd HH.mm} {name} (created {created}, edited {modified:MMM yyyy})"
        let subject = RenameSubject(
            url: URL(fileURLWithPath: "/P/IMG_1.jpg"), created: date("2023-01-02 10:00"),
            modified: date("2024-03-04 11:00"), photoTaken: date("2022-07-14 18:30")
        )
        let preview = BatchRename.preview([subject], rules: rules, exists: { _ in false })
        XCTAssertEqual(
            preview.rows.map(\.newName), ["2022-07-14 18.30 IMG_1 (created 2023-01-02, edited Mar 2024).jpg"]
        )
    }

    func testMissingPhotoDateBlocksTheRename() {
        var rules = RenameRules()
        rules.template = "{exif} {name}"
        let preview = BatchRename.preview(
            [RenameSubject(url: URL(fileURLWithPath: "/P/scan.png"))], rules: rules, exists: { _ in false }
        )
        XCTAssertEqual(preview.rows.map(\.problem), [.noPhotoDate])
        XCTAssertFalse(preview.canRename)
    }

    func testLoadReadsFileDatesAndTheEXIFDate() throws {
        let sandbox = try Sandbox()
        let photo = sandbox.url("photo.jpg")
        try FileManager.default.createDirectory(at: sandbox.root, withIntermediateDirectories: true)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithURL(photo as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let exif = [kCGImagePropertyExifDateTimeOriginal: "2021:12:24 20:15:00"]
        CGImageDestinationAddImage(
            destination, image, [kCGImagePropertyExifDictionary: exif] as CFDictionary
        )
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let subject = RenameSubject.load(photo)
        XCTAssertEqual(subject.photoTaken, date("2021-12-24 20:15"))
        XCTAssertNotNil(subject.created)
        XCTAssertNotNil(subject.modified)
        XCTAssertNil(try RenameSubject.load(sandbox.file("notes.txt")).photoTaken)
    }
}
