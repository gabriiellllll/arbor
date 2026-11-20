@testable import CanvasKit
import XCTest

@MainActor
final class FrameAnimatorTests: XCTestCase {
    func testEasingStartsAndEndsFlat() {
        XCTAssertEqual(FrameAnimator.eased(0), 0)
        XCTAssertEqual(FrameAnimator.eased(1), 1)
        XCTAssertEqual(FrameAnimator.eased(0.5), 0.5, accuracy: 0.0001)
        XCTAssertLessThan(FrameAnimator.eased(0.1), 0.1)
        XCTAssertEqual(FrameAnimator.eased(2), 1, "clamped")
    }

    func testInterpolationIsLinearInProgress() {
        let from = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = CGRect(x: 100, y: 200, width: 300, height: 100)
        XCTAssertEqual(FrameAnimator.interpolate(from, target, 0.5), CGRect(x: 50, y: 100, width: 200, height: 100))
    }

    func testStepsFollowTheEasedProgressThenLandOnTargets() {
        let id = PanelID()
        let start = CGRect(x: 0, y: 0, width: 100, height: 100)
        let target = CGRect(x: 200, y: 400, width: 100, height: 100)
        var clock = Date(timeIntervalSinceReferenceDate: 0)
        var applied: [CGRect] = []
        let animator = FrameAnimator { clock }
        animator.animate(from: [id: start], to: [id: target], duration: 1) { frames in
            frames[id].map { applied.append($0) }
        }

        clock += 0.5
        animator.tick()
        XCTAssertEqual(applied.last, FrameAnimator.interpolate(start, target, FrameAnimator.eased(0.5)))
        XCTAssertTrue(animator.isAnimating)

        clock += 0.6
        animator.tick()
        XCTAssertEqual(applied.last, target)
        XCTAssertFalse(animator.isAnimating)
    }

    func testTimerDrivenAnimationEndsExactlyOnTargets() {
        let id = PanelID()
        let target = CGRect(x: 100, y: 100, width: 300, height: 200)
        let done = expectation(description: "reaches target")
        let animator = FrameAnimator()
        animator.animate(from: [id: .zero], to: [id: target], duration: 0.05) { frames in
            if frames[id] == target {
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 5)
        XCTAssertFalse(animator.isAnimating)
    }

    func testZeroDurationAppliesImmediately() {
        let id = PanelID()
        var applied: [PanelID: CGRect] = [:]
        FrameAnimator().animate(from: [:], to: [id: .infinite], duration: 0) { applied = $0 }
        XCTAssertEqual(applied[id], .infinite)
    }
}
