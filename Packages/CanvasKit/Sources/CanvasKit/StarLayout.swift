import CoreGraphics
import Foundation

/// Radial layout: each root in the middle, descendants on rings by depth. Each node gets an
/// angular sector proportional to its number of leaves, nested inside its parent's sector.
/// Ring radii are the smallest that keep neighbors on a ring, and consecutive rings, apart
/// by a panel diagonal, so panels never overlap.
struct StarLayout {
    let forest: Forest

    private struct Placement {
        var angle: [PanelID: CGFloat] = [:]
        var smallestSector: [Int: CGFloat] = [:]
    }

    func frames(origin: CGPoint) -> [PanelID: CGRect] {
        var frames: [PanelID: CGRect] = [:]
        var left = origin.x
        for root in forest.roots {
            let local = star(root)
            // Explicit min/max: chaining CGRect.union rounds differently depending on order.
            let minX = local.values.map(\.minX).min() ?? 0
            let maxX = local.values.map(\.maxX).max() ?? 0
            let minY = local.values.map(\.minY).min() ?? 0
            for (id, frame) in local {
                frames[id] = frame.offsetBy(dx: left - minX, dy: origin.y - minY)
            }
            left += maxX - minX + LayoutEngine.treeGap
        }
        return frames
    }

    /// Frames of one root's tree, centered on the root at (0, 0).
    private func star(_ root: PanelID) -> [PanelID: CGRect] {
        var placement = Placement()
        // Sectors start on the left so a single child goes to the right of its parent.
        assignSectors(root, from: -.pi, to: .pi, level: 0, into: &placement)
        let radii = ringRadii(root: root, placement: placement)
        var frames: [PanelID: CGRect] = [:]
        for (id, angle) in placement.angle {
            guard let node = forest.nodes[id], let level = forest.depth[id] else { continue }
            let radius = radii[level] ?? 0
            let center = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            frames[id] = CGRect(
                x: center.x - node.size.width / 2, y: center.y - node.size.height / 2,
                width: node.size.width, height: node.size.height
            )
        }
        return frames
    }

    private func leaves(_ id: PanelID) -> Int {
        let children = forest.children[id] ?? []
        return children.isEmpty ? 1 : children.reduce(0) { $0 + leaves($1) }
    }

    private func assignSectors(
        _ id: PanelID, from start: CGFloat, to end: CGFloat, level: Int, into placement: inout Placement
    ) {
        placement.angle[id] = (start + end) / 2
        placement.smallestSector[level] = min(placement.smallestSector[level] ?? .infinity, end - start)
        let children = forest.children[id] ?? []
        let total = CGFloat(children.reduce(0) { $0 + leaves($1) })
        var angle = start
        for child in children {
            let span = (end - start) * CGFloat(leaves(child)) / total
            assignSectors(child, from: angle, to: angle + span, level: level + 1, into: &placement)
            angle += span
        }
    }

    private func ringRadii(root _: PanelID, placement: Placement) -> [Int: CGFloat] {
        var diagonal: [Int: CGFloat] = [:]
        for id in placement.angle.keys {
            guard let node = forest.nodes[id], let level = forest.depth[id] else { continue }
            diagonal[level] = max(diagonal[level] ?? 0, hypot(node.size.width, node.size.height))
        }
        let gap = LayoutEngine.siblingGap
        var radii: [Int: CGFloat] = [0: 0]
        let deepest = diagonal.keys.max() ?? 0
        guard deepest > 0 else { return radii }
        for level in 1 ... deepest {
            let size = diagonal[level] ?? 0
            let previous = radii[level - 1] ?? 0
            let clearRing = previous + ((diagonal[level - 1] ?? 0) + size) / 2 + gap
            // Neighbors on this ring are at least the smallest sector apart (capped at half a turn).
            let sector = min(placement.smallestSector[level] ?? .pi, .pi)
            let clearNeighbors = (size + gap) / (2 * sin(sector / 2))
            radii[level] = max(clearRing, clearNeighbors)
        }
        return radii
    }
}
