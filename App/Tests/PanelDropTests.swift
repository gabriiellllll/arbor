@testable import Arbor
import XCTest

/// Drops on a panel through AppKit's drop callbacks, with a stand-in for the drag session.
@MainActor
final class PanelDropTests: XCTestCase {
    private var folder: URL!
    private var panel: FolderPanelController!

    override func setUp() async throws {
        try await super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("PanelDropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("Sub"),
            withIntermediateDirectories: true
        )
        panel = FolderPanelController(url: folder, frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        panel.reload()
        let deadline = Date().addingTimeInterval(5)
        while panel.items.isEmpty, Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func info(dragging urls: [URL], mask: NSDragOperation) -> FakeDraggingInfo {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("PanelDropTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.writeObjects(urls as [NSURL])
        return FakeDraggingInfo(pasteboard: pasteboard, mask: mask)
    }

    func testDropOnAFolderRowMovesIntoIt() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString).txt")
        var droppedURLs: [URL] = []
        var dropped: (destination: URL, copying: Bool)?
        panel.onDropFiles = { urls, destination, copying in
            droppedURLs = urls
            dropped = (destination, copying)
        }
        let row = try XCTUnwrap(panel.rowIndex(forName: "Sub"))
        let drag = info(dragging: [file], mask: [.copy, .move])

        XCTAssertEqual(
            panel.tableView(panel.tableView, validateDrop: drag, proposedRow: row, proposedDropOperation: .on),
            .move
        )
        XCTAssertTrue(panel.tableView(panel.tableView, acceptDrop: drag, row: row, dropOperation: .on))
        XCTAssertEqual(droppedURLs, [file])
        XCTAssertEqual(dropped?.destination.lastPathComponent, "Sub")
        XCTAssertEqual(dropped?.copying, false)
    }

    func testOptionDragCopiesIntoThePanelFolder() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("drop-\(UUID().uuidString).txt")
        var dropped: (destination: URL, copying: Bool)?
        panel.onDropFiles = { dropped = ($1, $2) }
        // ⌥ leaves only copy in the source mask.
        let drag = info(dragging: [file], mask: [.copy])
        XCTAssertEqual(
            panel.tableView(panel.tableView, validateDrop: drag, proposedRow: 0, proposedDropOperation: .above),
            .copy
        )
        XCTAssertTrue(panel.tableView(panel.tableView, acceptDrop: drag, row: -1, dropOperation: .on))
        XCTAssertEqual(dropped?.destination, folder)
        XCTAssertEqual(dropped?.copying, true)
    }

    /// AppKit finds drag and drop callbacks through the Objective-C runtime, not Swift.
    func testDragAndDropCallbacksAreVisibleToAppKit() {
        let selectors = [
            #selector(NSTableViewDataSource.tableView(_:pasteboardWriterForRow:)),
            #selector(NSTableViewDataSource.tableView(_:validateDrop:proposedRow:proposedDropOperation:)),
            #selector(NSTableViewDataSource.tableView(_:acceptDrop:row:dropOperation:)),
            NSSelectorFromString("collectionView:pasteboardWriterForItemAtIndexPath:"),
            NSSelectorFromString("collectionView:validateDrop:proposedIndexPath:dropOperation:"),
            NSSelectorFromString("collectionView:acceptDrop:indexPath:dropOperation:"),
        ]
        for selector in selectors {
            XCTAssertTrue(panel.responds(to: selector), "\(selector) is not exposed to AppKit")
        }
    }

    func testDroppingItemsAlreadyHereIsRefused() {
        let inside = folder.appendingPathComponent("Sub")
        let drag = info(dragging: [inside], mask: [.copy, .move])
        XCTAssertEqual(
            panel.tableView(panel.tableView, validateDrop: drag, proposedRow: 0, proposedDropOperation: .above),
            []
        )
    }
}

/// The parts of a drag session the drop callbacks read.
@MainActor
final class FakeDraggingInfo: NSObject, @preconcurrency NSDraggingInfo {
    let draggingPasteboard: NSPasteboard
    let draggingSourceOperationMask: NSDragOperation
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1

    init(pasteboard: NSPasteboard, mask: NSDragOperation) {
        draggingPasteboard = pasteboard
        draggingSourceOperationMask = mask
    }

    var draggingDestinationWindow: NSWindow? {
        nil
    }

    var draggingLocation: NSPoint {
        .zero
    }

    var draggedImageLocation: NSPoint {
        .zero
    }

    var draggedImage: NSImage? {
        nil
    }

    var draggingSource: Any? {
        nil
    }

    var draggingSequenceNumber: Int {
        0
    }

    var springLoadingHighlight: NSSpringLoadingHighlight {
        .none
    }

    func slideDraggedImage(to _: NSPoint) {}

    func enumerateDraggingItems(
        options _: NSDraggingItemEnumerationOptions = [], for _: NSView?, classes _: [AnyClass],
        searchOptions _: [NSPasteboard.ReadingOptionKey: Any] = [:],
        using _: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}

    func resetSpringLoading() {}
}
