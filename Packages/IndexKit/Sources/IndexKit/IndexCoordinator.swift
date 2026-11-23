import Foundation

/// Runs the index: scans roots that need it, then follows FSEvents (catching up from the last
/// saved event after a relaunch) and keeps the index current. Work runs on one background queue;
/// reading document text runs on a second one, at the lowest priority.
public final class IndexCoordinator: @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case idle
        case scanning(path: String, items: Int)
        /// A background pass reading Finder tags after a scan.
        case readingTags(path: String)
    }

    /// Folders whose contents or sizes changed in the index.
    public var onChange: (@Sendable (Set<String>) -> Void)?
    public var onStatus: (@Sendable (Status) -> Void)?

    public let store: IndexStore
    private let queue = DispatchQueue(label: "app.arbor.IndexCoordinator", qos: .utility)
    private let control = ScanControl()
    private let contentQueue = DispatchQueue(label: "app.arbor.IndexCoordinator.content", qos: .background)
    private let contentLock = NSLock()
    private var contentPassQueued = false
    private lazy var watcher = FolderWatcher(latency: 1) { [weak self] changes in
        guard let self else { return }
        queue.async { self.apply(changes) }
    }

    public init(store: IndexStore) {
        self.store = store
    }

    deinit {
        control.cancel()
    }

    /// Scans what needs scanning, then watches every root. Returns immediately.
    public func start() {
        queue.async { [self] in
            do {
                try prepareRoots()
            } catch {
                // ponytail: scan errors leave the index as it was; surface them in the settings status (phase 4b).
                onStatus?(.idle)
            }
        }
    }

    /// Starts indexing a folder or volume: scans it, then watches it with the others.
    public func addRoot(path: String, exclusions: [String]) {
        queue.async { [self] in
            guard let root = try? store.addRoot(path: path, exclusions: exclusions) else { return }
            try? store.updateVolumes()
            try? scan(root)
            startWatching()
        }
    }

    /// Stops indexing a root and drops its items.
    public func removeRoot(_ rootID: Int64) {
        queue.async { [self] in
            guard let root = try? store.roots().first(where: { $0.id == rootID }) else { return }
            try? store.removeRoot(rootID)
            startWatching()
            onChange?([root.path])
        }
    }

    /// Changes a root's exclusions and scans it again with them.
    public func setExclusions(_ rootID: Int64, _ exclusions: [String]) {
        queue.async { [self] in
            try? store.setExclusions(rootID, exclusions)
            guard let root = try? store.roots().first(where: { $0.id == rootID }) else { return }
            try? scan(root)
            startWatching()
        }
    }

    /// Drops a root's index and scans it again.
    public func rebuild(_ rootID: Int64) {
        queue.async { [self] in
            guard let root = try? store.roots().first(where: { $0.id == rootID }) else { return }
            try? scan(root)
            startWatching()
        }
    }

    /// Stops watching and cancels a running scan, then waits for work in progress to end.
    public func stop() {
        control.cancel()
        watcher.watch([])
        queue.sync {}
        contentQueue.sync {}
    }

    /// Reads the text of new and changed documents, unless a pass is already waiting to start.
    private func readContents() {
        let queued = contentLock.withLock {
            defer { contentPassQueued = true }
            return contentPassQueued
        }
        guard !queued else { return }
        contentQueue.async { [self] in
            contentLock.withLock { contentPassQueued = false }
            if let read = try? store.readContents(control: control), read > 0 {
                onChange?([])
            }
        }
    }

    /// A disk was plugged in or out: unplugged roots are kept as a catalog, returning ones
    /// are brought up to date. Returns immediately.
    public func volumesChanged() {
        queue.async { [self] in try? prepareRoots() }
    }

    /// Brings every root up to date, one volume per thread, then watches the available ones.
    private func prepareRoots() throws {
        try store.updateVolumes()
        let byVolume = try Dictionary(grouping: store.roots()) { FolderWatcher.volumeUUID(for: $0.path) ?? $0.path }
        let volumes = Array(byVolume.values)
        DispatchQueue.concurrentPerform(iterations: volumes.count) { index in
            for root in volumes[index] {
                try? prepare(root)
            }
        }
        startWatching()
        readContents()
    }

    private func prepare(_ root: IndexRoot) throws {
        guard root.isAvailable else {
            if !root.isOffline {
                try store.setOffline(root.id, true)
                onChange?([root.path])
            }
            return
        }
        if Self.needsScan(root) {
            try scan(root)
        } else if root.isOffline {
            // ponytail: a returning disk is re-read in full (unchanged items kept), since it may have
            // changed on another Mac; replaying its own FSEvents history could make that faster.
            onStatus?(.scanning(path: root.path, items: 0))
            try store.setLastEventID(root.id, FolderWatcher.currentEventID)
            try IndexUpdater(store: store).refreshAll(root, control: control)
            try store.setOffline(root.id, false)
            onStatus?(.idle)
            onChange?([root.path])
        }
    }

    /// A full scan is needed when never scanned, or when the volume's event history changed
    /// (event IDs from another history mean nothing).
    static func needsScan(_ root: IndexRoot) -> Bool {
        root.scannedAt == nil || root.lastEventID == nil || root.volumeUUID != FolderWatcher.volumeUUID(for: root.path)
    }

    /// Scans a root again from scratch, unless its folder or disk is missing (its items are then
    /// kept as a catalog).
    private func scan(_ root: IndexRoot) throws {
        guard root.isAvailable else { return }
        // Changes during the scan are replayed afterwards, from this event.
        let eventID = FolderWatcher.currentEventID
        let path = root.path
        onStatus?(.scanning(path: path, items: 0))
        try IndexScanner(store: store).scan(root, control: control) { [weak self] count in
            self?.onStatus?(.scanning(path: path, items: count))
        }
        try store.markScanned(root.id, eventID: eventID, volumeUUID: FolderWatcher.volumeUUID(for: path))
        try store.setOffline(root.id, false)
        onChange?([path])
        onStatus?(.readingTags(path: path))
        try IndexScanner(store: store).readTags(root, control: control)
        onStatus?(.idle)
        onChange?([path])
        readContents()
    }

    private func startWatching() {
        guard let roots = try? store.roots().filter(\.isAvailable), !roots.isEmpty else {
            watcher.watch([])
            return
        }
        let since = roots.compactMap(\.lastEventID).min()
        watcher.watch(Set(roots.map(\.path)), since: since)
    }

    private func apply(_ changes: [FolderChange]) {
        guard let affected = try? IndexUpdater(store: store).apply(changes) else { return }
        if let latest = changes.map(\.eventID).max(), latest > 0, let roots = try? store.roots() {
            for root in roots where (root.lastEventID ?? 0) < latest {
                try? store.setLastEventID(root.id, latest)
            }
        }
        if !affected.isEmpty {
            onChange?(affected)
            readContents()
        }
    }
}
