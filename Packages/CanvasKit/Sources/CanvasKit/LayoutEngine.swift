import CoreGraphics

/// How panels are arranged on the canvas.
public enum CanvasLayout: String, CaseIterable, Codable, Sendable {
    case treeRight, treeDown, star, manual
}

/// A panel as the layout engine sees it. Children are laid out in the order the nodes are given.
public struct LayoutNode: Equatable, Sendable {
    public let id: PanelID
    public let parent: PanelID?
    public let size: CGSize

    public init(id: PanelID, parent: PanelID?, size: CGSize) {
        self.id = id
        self.parent = parent
        self.size = size
    }
}

/// Computes deterministic, non-overlapping panel frames for the automatic layouts.
public enum LayoutEngine {
    /// Between depth columns in the tree-right layout.
    public static let columnGap: CGFloat = 80
    /// Between depth rows in the tree-down layout.
    public static let levelGap: CGFloat = 72
    /// Between sibling subtrees.
    public static let siblingGap: CGFloat = 24
    /// Between root trees.
    public static let treeGap: CGFloat = 80

    /// Frames for every node reachable from a root. Manual layout returns no frames: panels
    /// keep where the user put them.
    public static func frames(for nodes: [LayoutNode], layout: CanvasLayout, origin: CGPoint) -> [PanelID: CGRect] {
        let forest = Forest(nodes)
        switch layout {
        case .manual: return [:]
        case .treeRight: return TreeLayout(forest: forest, horizontal: true).frames(origin: origin)
        case .treeDown: return TreeLayout(forest: forest, horizontal: false).frames(origin: origin)
        case .star: return StarLayout(forest: forest).frames(origin: origin)
        }
    }
}

/// Nodes indexed by parent, with depths. Nodes whose parent is missing count as roots.
struct Forest {
    let nodes: [PanelID: LayoutNode]
    let roots: [PanelID]
    let children: [PanelID: [PanelID]]
    let depth: [PanelID: Int]

    init(_ list: [LayoutNode]) {
        let nodes = Dictionary(list.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var children: [PanelID: [PanelID]] = [:]
        var roots: [PanelID] = []
        for node in list {
            if let parent = node.parent, nodes[parent] != nil {
                children[parent, default: []].append(node.id)
            } else {
                roots.append(node.id)
            }
        }
        var depth: [PanelID: Int] = [:]
        var queue = roots.map { ($0, 0) }
        while let (id, level) = queue.popLast() {
            guard depth[id] == nil else { continue }
            depth[id] = level
            queue += (children[id] ?? []).map { ($0, level + 1) }
        }
        self.nodes = nodes
        self.roots = roots
        self.children = children
        self.depth = depth
    }
}

/// Tidy tree: each depth gets its own column (or row), wide enough for its widest panel;
/// each subtree gets its own band across. Bands and columns are disjoint, so panels
/// never overlap.
struct TreeLayout {
    let forest: Forest
    /// Depth runs along x (tree right) or y (tree down).
    let horizontal: Bool

    func frames(origin: CGPoint) -> [PanelID: CGRect] {
        let levelStarts = levelStarts(from: horizontal ? origin.x : origin.y)
        var frames: [PanelID: CGRect] = [:]
        var cross = horizontal ? origin.y : origin.x
        for root in forest.roots {
            cross += place(root, at: cross, levelStarts: levelStarts, into: &frames) + LayoutEngine.treeGap
        }
        return frames
    }

    private func mainExtent(_ size: CGSize) -> CGFloat {
        horizontal ? size.width : size.height
    }

    private func crossExtent(_ size: CGSize) -> CGFloat {
        horizontal ? size.height : size.width
    }

    private func levelStarts(from start: CGFloat) -> [CGFloat] {
        let gap = horizontal ? LayoutEngine.columnGap : LayoutEngine.levelGap
        let deepest = forest.depth.values.max() ?? 0
        var extents = Array(repeating: CGFloat(0), count: deepest + 1)
        for (id, level) in forest.depth {
            if let node = forest.nodes[id] {
                extents[level] = max(extents[level], mainExtent(node.size))
            }
        }
        var starts: [CGFloat] = []
        var position = start
        for extent in extents {
            starts.append(position)
            position += extent + gap
        }
        return starts
    }

    /// Places the subtree of `id` starting at `crossStart`; returns the cross extent it uses.
    private func place(
        _ id: PanelID, at crossStart: CGFloat, levelStarts: [CGFloat], into frames: inout [PanelID: CGRect]
    ) -> CGFloat {
        guard let node = forest.nodes[id], let level = forest.depth[id] else { return 0 }
        let main = levelStarts[level]
        frames[id] = CGRect(
            origin: horizontal ? CGPoint(x: main, y: crossStart) : CGPoint(x: crossStart, y: main),
            size: node.size
        )
        var cross = crossStart
        let children = forest.children[id] ?? []
        for child in children {
            cross += place(child, at: cross, levelStarts: levelStarts, into: &frames) + LayoutEngine.siblingGap
        }
        let childrenExtent = children.isEmpty ? 0 : cross - LayoutEngine.siblingGap - crossStart
        return max(crossExtent(node.size), childrenExtent)
    }
}
