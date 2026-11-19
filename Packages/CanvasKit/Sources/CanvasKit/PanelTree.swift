import CoreGraphics
import Foundation

public struct PanelID: Hashable, Codable, Sendable {
    public let rawValue: UUID

    public init() {
        rawValue = UUID()
    }
}

/// A panel on the canvas. `Content` is whatever the panel shows (the app uses a folder URL);
/// `sourceKey` identifies the row of the parent panel the panel was opened from.
public struct CanvasPanel<Content> {
    public let id: PanelID
    public let parent: PanelID?
    public let sourceKey: String?
    public var content: Content
    public var frame: CGRect
}

extension CanvasPanel: Sendable where Content: Sendable {}

/// The tree of panels on the canvas. Each panel's children are the branches opened from
/// its rows; keeping them in sync with the parent's selection gives Finder-column behavior
/// (selecting another row replaces the branch) and multiple branches for multiple rows.
public struct PanelTree<Content> {
    public typealias Panel = CanvasPanel<Content>

    public struct SyncResult {
        public let added: [PanelID]
        public let removed: [PanelID]
    }

    public private(set) var panels: [PanelID: Panel] = [:]
    /// Insertion order, so iteration is deterministic.
    private var order: [PanelID] = []

    public init() {}

    public subscript(id: PanelID) -> Panel? {
        panels[id]
    }

    public var roots: [PanelID] {
        order.filter { panels[$0]?.parent == nil }
    }

    public func children(of id: PanelID) -> [Panel] {
        order.compactMap { panels[$0] }.filter { $0.parent == id }
    }

    /// Panels from the root down to `id`.
    public func chain(to id: PanelID) -> [PanelID] {
        var chain: [PanelID] = []
        var current: PanelID? = id
        while let id = current, let panel = panels[id] {
            chain.insert(id, at: 0)
            current = panel.parent
        }
        return chain
    }

    public mutating func addRoot(content: Content, frame: CGRect) -> PanelID {
        insert(Panel(id: PanelID(), parent: nil, sourceKey: nil, content: content, frame: frame))
    }

    public mutating func setFrame(_ frame: CGRect, for id: PanelID) {
        panels[id]?.frame = frame
    }

    /// Removes a panel and all its descendants. Returns every removed ID.
    @discardableResult
    public mutating func remove(_ id: PanelID) -> [PanelID] {
        var removed = [id]
        for child in children(of: id) {
            removed += remove(child.id)
        }
        panels[id] = nil
        order.removeAll { $0 == id }
        return removed
    }

    /// Makes the children of `parent` exactly the `requested` keys: keeps matching children
    /// (with their subtrees), removes the others, and adds the missing ones at the frame
    /// returned by `place`.
    @discardableResult
    public mutating func syncChildren(
        of parentID: PanelID,
        to requested: [(key: String, content: Content)],
        place: (Panel, String) -> CGRect
    ) -> SyncResult {
        guard let parent = panels[parentID] else { return SyncResult(added: [], removed: []) }
        let keys = Set(requested.map(\.key))
        var removed: [PanelID] = []
        for child in children(of: parentID) where !keys.contains(child.sourceKey ?? "") {
            removed += remove(child.id)
        }
        let existing = Set(children(of: parentID).compactMap(\.sourceKey))
        var added: [PanelID] = []
        for request in requested where !existing.contains(request.key) {
            let frame = place(parent, request.key)
            added.append(insert(Panel(
                id: PanelID(), parent: parentID, sourceKey: request.key, content: request.content, frame: frame
            )))
        }
        return SyncResult(added: added, removed: removed)
    }

    private mutating func insert(_ panel: Panel) -> PanelID {
        panels[panel.id] = panel
        order.append(panel.id)
        return panel.id
    }
}

extension PanelTree: Sendable where Content: Sendable {}
