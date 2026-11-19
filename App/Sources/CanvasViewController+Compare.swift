import AppKit
import CanvasKit

/// Two folders compared side by side.
struct CompareSession {
    let left: PanelID
    let right: PanelID

    func contains(root: PanelID) -> Bool {
        root == left || root == right
    }
}

/// Side-by-side comparison: two sibling folders open as two chains in parallel columns.
/// Opening a folder on one side opens the folder with the same name on the other side, on the
/// same row; items present on one side only are marked.
extension CanvasViewController {
    /// Exactly two folders are selected in the active panel.
    var canCompareSelection: Bool {
        activePanel.flatMap { panels[$0] }?.selectedItems.filter(\.isFolder).count == 2
    }

    func compareSelection() {
        guard let id = activePanel, let panel = panels[id] else { return }
        let folders = panel.selectedItems.filter(\.isFolder)
        guard folders.count == 2 else { return }
        endComparison()
        let left = addRoot(folders[0].url, colorIndex: nil)
        let right = addRoot(folders[1].url, colorIndex: nil)
        compare = CompareSession(left: left, right: right)
        updateComparisonMarks()
        activePanel = left
        applyLayout(revealing: right)
    }

    func endComparison() {
        guard let compare else { return }
        self.compare = nil
        for root in [compare.left, compare.right] {
            rootColors[root] = nil
            removePanels(tree.remove(root))
        }
        applyLayout(revealing: nil)
    }

    func isCompared(_ id: PanelID) -> Bool {
        comparedPanels().contains(id)
    }

    func comparedPanels() -> Set<PanelID> {
        compare.map { Set(lane($0.left) + lane($0.right)) } ?? []
    }

    /// A compared root and the chain of folders opened below it.
    func lane(_ root: PanelID) -> [PanelID] {
        var ids = [root]
        while let last = ids.last, let child = tree.children(of: last).first {
            ids.append(child.id)
        }
        return ids
    }

    /// Frames of the compared chains: after the other panels in automatic layouts, where the
    /// left root is in manual layout.
    func compareTargets(besides others: [PanelID: CGRect]) -> [PanelID: CGRect] {
        guard let compare else { return [:] }
        let left = lane(compare.left)
        let right = lane(compare.right)
        var origin = tree[compare.left]?.frame.origin ?? .zero
        if layout != .manual, let maxX = others.values.map(\.maxX).max(), let minY = others.values.map(\.minY).min() {
            origin = CGPoint(x: maxX + LayoutEngine.treeGap, y: minY)
        }
        let size = { (id: PanelID) in self.tree[id]?.frame.size ?? Self.panelSize }
        let frames = CompareLayout.frames(left: left.map(size), right: right.map(size), origin: origin)
        var targets: [PanelID: CGRect] = [:]
        for (id, frame) in zip(left, frames.left) {
            targets[id] = frame
        }
        for (id, frame) in zip(right, frames.right) {
            targets[id] = frame
        }
        return targets
    }

    /// The panel at the same depth in the other chain.
    func counterpart(of id: PanelID) -> PanelID? {
        guard let compare else { return nil }
        let left = lane(compare.left)
        let right = lane(compare.right)
        if let depth = left.firstIndex(of: id) {
            return depth < right.count ? right[depth] : nil
        }
        if let depth = right.firstIndex(of: id) {
            return depth < left.count ? left[depth] : nil
        }
        return nil
    }

    /// Selects the same folder names in the counterpart panel (not mirrored back).
    func mirrorSelection(from id: PanelID, names: Set<String>) {
        guard !isMirroringSelection, let other = counterpart(of: id), let panel = panels[other],
              Set(panel.selectedItems.filter(\.isFolder).map(\.name)) != names else { return }
        isMirroringSelection = true
        panel.select(names: names)
        isMirroringSelection = false
    }

    /// Gives each compared panel the names of its counterpart (none when the other chain is
    /// shorter, so everything shows as present on one side only).
    func updateComparisonMarks() {
        guard let compare else { return }
        let left = lane(compare.left)
        let right = lane(compare.right)
        for depth in 0 ..< max(left.count, right.count) {
            let leftPanel = depth < left.count ? panels[left[depth]] : nil
            let rightPanel = depth < right.count ? panels[right[depth]] : nil
            leftPanel?.counterpartNames = Set(rightPanel?.items.map(\.name) ?? [])
            rightPanel?.counterpartNames = Set(leftPanel?.items.map(\.name) ?? [])
        }
    }
}
