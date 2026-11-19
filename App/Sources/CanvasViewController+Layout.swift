import AppKit
import CanvasKit

/// Layouts: automatic layouts arrange every panel (animated, branches follow); manual keeps
/// where the user put panels and remembers it. Dragging a panel switches to manual.
extension CanvasViewController {
    func layoutDidChange(from old: CanvasLayout) {
        UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutDefaultsKey)
        if old == .manual {
            manualFrames = currentFrames()
        }
        guard layout == .manual else {
            applyLayout(revealing: nil)
            return
        }
        guard !keepsFramesOnManualSwitch else { return }
        var targets = currentFrames()
        for (id, frame) in manualFrames where targets[id] != nil {
            targets[id] = frame
        }
        targets.merge(compareTargets(besides: [:])) { $1 }
        animate(to: targets, revealing: nil)
    }

    func currentFrames() -> [PanelID: CGRect] {
        panels.mapValues(\.panelView.frame)
    }

    /// Arranges panels for the current layout (animated), then reveals `id` if given.
    func applyLayout(revealing id: PanelID?) {
        animate(to: layoutTargets(), revealing: id)
    }

    func layoutTargets() -> [PanelID: CGRect] {
        let compared = comparedPanels()
        var targets: [PanelID: CGRect] = [:]
        if layout != .manual {
            let nodes = orderedNodes().filter { !compared.contains($0.id) }
            let origin = tree.roots.first { !compared.contains($0) }.flatMap { tree[$0]?.frame.origin } ?? .zero
            targets = LayoutEngine.frames(for: nodes, layout: layout, origin: origin)
        }
        targets.merge(compareTargets(besides: targets)) { $1 }
        return targets
    }

    /// Panels depth first, children in the order of their source rows.
    private func orderedNodes() -> [LayoutNode] {
        var nodes: [LayoutNode] = []
        func visit(_ id: PanelID) {
            guard let panel = tree[id] else { return }
            nodes.append(LayoutNode(id: id, parent: panel.parent, size: panel.frame.size))
            let rows = panels[id]
            let children = tree.children(of: id).sorted {
                (rows?.rowIndex(forName: $0.sourceKey ?? "") ?? .max) <
                    (rows?.rowIndex(forName: $1.sourceKey ?? "") ?? .max)
            }
            children.forEach { visit($0.id) }
        }
        tree.roots.forEach(visit)
        return nodes
    }

    func animate(to targets: [PanelID: CGRect], revealing id: PanelID?) {
        let start = currentFrames()
        let moving = targets.filter { start[$0.key] != $0.value }
        if moving.isEmpty {
            updateBranches()
        } else {
            animator.animate(from: start, to: moving) { [weak self] frames in self?.apply(frames) }
        }
        if let id, let frame = targets[id] ?? tree[id]?.frame {
            let context = tree[id]?.parent.flatMap { targets[$0] ?? tree[$0]?.frame }
            canvasView.reveal(frame, context: context)
        }
    }

    private func apply(_ frames: [PanelID: CGRect]) {
        for (id, frame) in frames {
            panels[id]?.panelView.frame = frame
            tree.setFrame(frame, for: id)
        }
        updateBranches()
    }

    // MARK: - Dragging

    func panelDragged(_ id: PanelID) {
        guard let frame = panels[id]?.panelView.frame else { return }
        let moved = frame.origin != tree[id]?.frame.origin
        tree.setFrame(frame, for: id)
        updateBranches()
        if moved, layout != .manual, !isCompared(id) {
            keepsFramesOnManualSwitch = true
            layout = .manual
            keepsFramesOnManualSwitch = false
        }
    }

    func panelDragEnded(_ id: PanelID) {
        if layout == .manual {
            manualFrames = currentFrames()
        }
        // Automatic layouts re-flow after a resize; compared chains re-align after any change.
        if layout != .manual || isCompared(id) {
            applyLayout(revealing: nil)
        }
    }
}
