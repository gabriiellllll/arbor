/// Back / forward history of canvas navigation, like a browser's.
public struct NavigationHistory<Entry: Equatable> {
    public private(set) var entries: [Entry] = []
    private var index = -1
    private let limit: Int

    public init(limit: Int = 100) {
        self.limit = limit
    }

    public var current: Entry? {
        entries.indices.contains(index) ? entries[index] : nil
    }

    public var canGoBack: Bool {
        index > 0
    }

    public var canGoForward: Bool {
        index < entries.count - 1
    }

    /// Records a visit. Drops the forward entries, ignores a repeat of the current entry, and
    /// keeps at most `limit` entries.
    public mutating func visit(_ entry: Entry) {
        guard entry != current else { return }
        entries.removeSubrange((index + 1)...)
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        index = entries.count - 1
    }

    public mutating func back() -> Entry? {
        guard canGoBack else { return nil }
        index -= 1
        return current
    }

    public mutating func forward() -> Entry? {
        guard canGoForward else { return nil }
        index += 1
        return current
    }
}

extension NavigationHistory: Sendable where Entry: Sendable {}
