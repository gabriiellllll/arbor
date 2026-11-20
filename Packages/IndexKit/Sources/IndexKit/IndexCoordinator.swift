import Foundation

/// Runs the index: scans roots that need it, then follows FSEvents (catching up from the last
/// saved event after a relaunch) and keeps the index current. Work runs on one background queue.
public final class IndexCoordinator: @unchecked Sendable {
    public enum Status: Equatable, Sendable {
        case idle
        case scanning(path: String, items: Int)
    }

    /// Folders whose contents or sizes changed in the index.
    public var onChange: (@Sendable (Set<String>) -> Void)?
    public var onStatus: (@Sendable (Status) -> Void)?

    public let store: IndexStore
    private let queue = DispatchQueue(label: "app.arbor.IndexCoordinator", qos: .utility)
    private let control = ScanControl()
    private lazy var watcher = FolderWatcher(latency: 1) { [weak self] changes in
        self?.queue.async { self?.apply(changes) }
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

    /// Drops a root's index and scans it again.
    public func rebuild(_ rootID: Int64) {
        queue.async { [self] in
            guard let root = try? store.roots().first(where: { $0.id == rootID }) else { return }
            try? scan(root)
            startWatching()
        }
    }

    public func stop() {
        control.cancel()
        watcher.watch([])
    }

    /// Scans the roots that need it, one volume per thread, then watches all roots.
    private func prepareRoots() throws {
        let byVolume = try Dictionary(grouping: store.roots().filter(Self.needsScan)) {
            FolderWatcher.volumeUUID(for: $0.path) ?? $0.path
        }
        let volumes = Array(byVolume.values)
        DispatchQueue.concurrentPerform(iterations: volumes.count) { index in
            for root in volumes[index] {
                try? scan(root)
            }
        }
        startWatching()
    }

    /// A full scan is needed when never scanned, or when the volume's event history changed
    /// (event IDs from another history mean nothing).
    static func needsScan(_ root: IndexRoot) -> Bool {
        root.scannedAt == nil || root.lastEventID == nil || root.volumeUUID != FolderWatcher.volumeUUID(for: root.path)
    }

    private func scan(_ root: IndexRoot) throws {
        // Changes during the scan are replayed afterwards, from this event.
        let eventID = FolderWatcher.currentEventID
        let path = root.path
        onStatus?(.scanning(path: path, items: 0))
        try IndexScanner(store: store).scan(root, control: control) { [weak self] count in
            self?.onStatus?(.scanning(path: path, items: count))
        }
        try store.markScanned(root.id, eventID: eventID, volumeUUID: FolderWatcher.volumeUUID(for: path))
        onStatus?(.idle)
        onChange?([path])
    }

    private func startWatching() {
        guard let roots = try? store.roots(), !roots.isEmpty else { return }
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
        }
    }
}
