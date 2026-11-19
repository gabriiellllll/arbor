@testable import CanvasKit
import XCTest

@MainActor
final class CanvasViewTests: XCTestCase {
    private var canvas: CanvasView!

    override func setUp() async throws {
        canvas = CanvasView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    func testStartsAtFullSizeNearTheOrigin() {
        XCTAssertEqual(canvas.magnification, 1)
        XCTAssertEqual(canvas.visibleCanvasRect.origin, CGPoint(x: -40, y: -40))
        XCTAssertEqual(canvas.visibleCanvasRect.size, CGSize(width: 800, height: 600))
    }

    func testDocumentCoordinatesAreCanvasCoordinates() {
        let panel = NSView(frame: CGRect(x: 100, y: 50, width: 300, height: 200))
        canvas.documentView.addSubview(panel)
        XCTAssertTrue(canvas.documentView.isFlipped)
        XCTAssertEqual(panel.frame.origin, CGPoint(x: 100, y: 50))
    }

    func testSetZoomClampsAndKeepsCenter() {
        let center = CGPoint(x: canvas.visibleCanvasRect.midX, y: canvas.visibleCanvasRect.midY)
        canvas.setZoom(2, animated: false)
        XCTAssertEqual(canvas.magnification, 2, accuracy: 0.001)
        XCTAssertEqual(canvas.visibleCanvasRect.width, 400, accuracy: 0.5)
        XCTAssertEqual(canvas.visibleCanvasRect.midX, center.x, accuracy: 0.5)
        XCTAssertEqual(canvas.visibleCanvasRect.midY, center.y, accuracy: 0.5)
        canvas.setZoom(100, animated: false)
        XCTAssertEqual(canvas.magnification, Zoom.maximum, accuracy: 0.001)
    }

    func testRepeatedAnimatedZoomKeepsStepping() {
        for _ in 0 ..< 4 {
            canvas.zoomOut()
        }
        XCTAssertEqual(canvas.targetMagnification, 0.5, accuracy: 0.001)
        canvas.zoomIn()
        XCTAssertEqual(canvas.targetMagnification, 0.67, accuracy: 0.001)
    }

    func testRevealScrollsToTarget() {
        let target = CGRect(x: 5000, y: 3000, width: 300, height: 200)
        canvas.reveal(target, animated: false)
        XCTAssertTrue(canvas.visibleCanvasRect.contains(target))
    }

    func testViewportChangeIsReported() {
        var calls = 0
        canvas.onViewportChange = { calls += 1 }
        canvas.scroll(toCanvasOrigin: CGPoint(x: 10, y: 10))
        XCTAssertGreaterThan(calls, 0)
    }

    func testHandToolCapturesClicksOverPanels() {
        let panel = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        canvas.documentView.addSubview(panel)
        let point = canvas.documentView.convert(CGPoint(x: 10, y: 10), to: canvas.documentView.superview)
        XCTAssertTrue(canvas.documentView.hitTest(point) === panel)
        canvas.isHandToolActive = true
        XCTAssertTrue(canvas.documentView.hitTest(point) === canvas.documentView)
    }

    func testEmptyCanvasHitsDocumentNotBranchHost() {
        let point = canvas.documentView.convert(CGPoint(x: 500, y: 500), to: canvas.documentView.superview)
        XCTAssertTrue(canvas.documentView.hitTest(point) === canvas.documentView)
    }

    func testBranchesKeepOneLayerPerChild() throws {
        let first = PanelID()
        let second = PanelID()
        let curve = BranchCurve(from: .zero, to: CGPoint(x: 100, y: 50))
        canvas.branchesView.setBranches([first: (curve, .red), second: (curve, .blue)])
        XCTAssertEqual(canvas.branchesView.layer?.sublayers?.count, 2)
        canvas.branchesView.setBranches([second: (curve, .blue)])
        let layers = try XCTUnwrap(canvas.branchesView.layer?.sublayers as? [CAShapeLayer])
        XCTAssertEqual(layers.count, 1)
        XCTAssertEqual(layers[0].path, curve.path)
    }

    func testEveryBackgroundStyleDraws() {
        for style in CanvasBackground.allCases {
            canvas.background = style
            XCTAssertNotNil(canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds).map {
                canvas.cacheDisplay(in: canvas.bounds, to: $0)
            })
        }
    }
}
