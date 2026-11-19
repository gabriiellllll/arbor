import CoreGraphics
import Foundation

/// Animates panel frames frame by frame, so the caller can update branches on every step
/// and they stay attached while panels move.
@MainActor
public final class FrameAnimator {
    public static let duration: TimeInterval = 0.35

    private var timer: Timer?

    public init() {}

    /// Ease in-out (cubic).
    public nonisolated static func eased(_ progress: Double) -> Double {
        let time = min(max(progress, 0), 1)
        return time < 0.5 ? 4 * time * time * time : 1 - pow(-2 * time + 2, 3) / 2
    }

    public nonisolated static func interpolate(_ from: CGRect, _ target: CGRect, _ progress: Double) -> CGRect {
        let fraction = CGFloat(progress)
        return CGRect(
            x: from.minX + (target.minX - from.minX) * fraction,
            y: from.minY + (target.minY - from.minY) * fraction,
            width: from.width + (target.width - from.width) * fraction,
            height: from.height + (target.height - from.height) * fraction
        )
    }

    private struct Run {
        let began: Date
        let duration: TimeInterval
        let start: [PanelID: CGRect]
        let targets: [PanelID: CGRect]
        let apply: ([PanelID: CGRect]) -> Void
    }

    private var run: Run?

    // ponytail: Timer at 120 Hz; switch to a display link if steps visibly stutter.
    /// Moves every panel in `targets` from its frame in `start` (or directly, if missing) to
    /// its target, calling `apply` on each step and once more with the exact targets.
    /// Starting a new animation cancels the running one.
    public func animate(
        from start: [PanelID: CGRect],
        to targets: [PanelID: CGRect],
        duration: TimeInterval = FrameAnimator.duration,
        apply: @escaping ([PanelID: CGRect]) -> Void
    ) {
        timer?.invalidate()
        timer = nil
        guard duration > 0 else {
            run = nil
            apply(targets)
            return
        }
        run = Run(began: Date(), duration: duration, start: start, targets: targets, apply: apply)
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let run else { return }
        let progress = Self.eased(Date().timeIntervalSince(run.began) / run.duration)
        guard progress < 1 else {
            timer?.invalidate()
            timer = nil
            self.run = nil
            run.apply(run.targets)
            return
        }
        var frames: [PanelID: CGRect] = [:]
        for (id, target) in run.targets {
            frames[id] = Self.interpolate(run.start[id] ?? target, target, progress)
        }
        run.apply(frames)
    }

    public var isAnimating: Bool {
        timer != nil
    }
}
