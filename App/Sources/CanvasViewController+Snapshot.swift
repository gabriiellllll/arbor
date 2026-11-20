import AppKit
import CanvasKit

/// What a workspace remembers of its canvas.
struct CanvasSnapshot: Codable, Equatable {
    struct Root: Codable, Equatable {
        var path: String
        var colorIndex: Int
    }

    var layout: CanvasLayout = .treeRight
    var zoom: Double = 1
    var visibleOrigin = CGPoint(x: -40, y: -40)
    var roots: [Root] = []
    /// Folder names selected in each open folder, by folder path: they reopen the branches.
    var selections: [String: [String]] = [:]
    /// Panel frames by folder path.
    var frames: [String: CGRect] = [:]
    /// Paths of the two compared folders, if a comparison is open.
    var compared: [String]?
}

extension CanvasViewController {
    func snapshot() -> CanvasSnapshot {
        var snapshot = CanvasSnapshot(
            layout: layout,
            zoom: Double(canvasView.targetMagnification),
            visibleOrigin: canvasView.visibleCanvasRect.origin
        )
        let comparedRoots = compare.map { [$0.left, $0.right] } ?? []
        snapshot.roots = tree.roots.filter { !comparedRoots.contains($0) }.compactMap { id in
            tree[id].map { CanvasSnapshot.Root(path: $0.content.path, colorIndex: rootColors[id] ?? 0) }
        }
        for panel in panels.values {
            let names = panel.selectedItems.filter(\.isFolder).map(\.name)
            if !names.isEmpty {
                snapshot.selections[panel.url.path] = names
            }
            snapshot.frames[panel.url.path] = panel.panelView.frame
        }
        if let compare, let left = tree[compare.left], let right = tree[compare.right] {
            snapshot.compared = [left.content.path, right.content.path]
        }
        return snapshot
    }

    /// Replaces the canvas with `snapshot`. Roots open now; branches reopen as their parent
    /// folders load.
    func restore(_ snapshot: CanvasSnapshot) {
        endComparison()
        for root in tree.roots {
            removePanels(tree.remove(root))
        }
        rootColors = [:]
        manualFrames = [:]
        activePanel = nil
        history = NavigationHistory()
        pendingSelections = snapshot.selections
        pendingFrames = snapshot.frames

        keepsFramesOnManualSwitch = true
        layout = snapshot.layout
        keepsFramesOnManualSwitch = false
        canvasView.setZoom(snapshot.zoom, animated: false)
        canvasView.scroll(toCanvasOrigin: snapshot.visibleOrigin)

        for root in snapshot.roots {
            _ = addRoot(URL(fileURLWithPath: root.path, isDirectory: true), colorIndex: root.colorIndex)
        }
        if let paths = snapshot.compared, paths.count == 2 {
            let left = addRoot(URL(fileURLWithPath: paths[0], isDirectory: true), colorIndex: nil)
            let right = addRoot(URL(fileURLWithPath: paths[1], isDirectory: true), colorIndex: nil)
            compare = CompareSession(left: left, right: right)
        }
        if layout == .manual {
            manualFrames = currentFrames()
        }
        onInspectedItemChange?(nil)
        applyLayout(revealing: nil)
    }
}
