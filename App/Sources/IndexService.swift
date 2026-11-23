import AppKit
import DiskKit
import IndexKit

/// The app's file index: opens it, indexes the startup volume on first launch, keeps it
/// current, and answers folder sizes for panels.
@MainActor
final class IndexService {
    /// System areas left out of the startup volume index.
    static let defaultExclusions = [
        "/System", "/private", "/dev", "/Volumes", "/cores", "/.vol", "/.fseventsd",
        "/.Spotlight-V100", "/.DocumentRevisions-V100", "/.MobileBackups", "/.Trashes",
    ]

    let store: IndexStore
    private let coordinator: IndexCoordinator
    /// Folders whose sizes changed.
    var onChange: ((Set<String>) -> Void)?
    private(set) var status: IndexCoordinator.Status = .idle
    var onStatus: ((IndexCoordinator.Status) -> Void)?
    private var volumeObservers: [any NSObjectProtocol] = []

    init(store: IndexStore) {
        self.store = store
        coordinator = IndexCoordinator(store: store)
        coordinator.onChange = { [weak self] paths in
            Task { @MainActor in self?.onChange?(paths) }
        }
        coordinator.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.status = status
                self?.onStatus?(status)
            }
        }
    }

    /// `~/Library/Application Support/Arbor/index.sqlite`, indexing the startup volume if empty.
    static func openDefault() throws -> IndexService {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let store = try IndexStore.open(at: support.appendingPathComponent("Arbor/index.sqlite"))
        if try store.roots().isEmpty {
            _ = try store.addRoot(path: "/", exclusions: defaultExclusions)
        }
        return IndexService(store: store)
    }

    /// UI tests index only their fixture folder, in a database next to it. With `unpluggedDisk`,
    /// the catalog also holds a disk that is not plugged in (a folder indexed, then deleted).
    static func openForUITests(fixture: URL, unpluggedDisk: URL? = nil) throws -> IndexService {
        let store = try IndexStore.open(at: fixture.deletingLastPathComponent().appendingPathComponent("index.sqlite"))
        _ = try store.addRoot(path: FolderWatcher.canonicalPath(of: fixture), exclusions: [])
        if let unpluggedDisk {
            let root = try store.addRoot(path: FolderWatcher.canonicalPath(of: unpluggedDisk), exclusions: [])
            try IndexScanner(store: store).scan(root)
            try store.updateVolumes([MountedVolume(path: root.path, uuid: "ARBOR-UI-TEST-DISK")])
            let details = DiskDetails(
                name: unpluggedDisk.lastPathComponent, vendor: "Arbor", model: "UI Test Disk",
                serialNumber: "UITEST", connection: "USB", capacity: 500_000_000_000, fileSystem: "APFS"
            )
            try store.setDetails(root.id, JSONEncoder().encode(details))
            try FileManager.default.removeItem(at: unpluggedDisk)
        }
        return IndexService(store: store)
    }

    func start() {
        coordinator.start()
        saveDiskDetails()
        let center = NSWorkspace.shared.notificationCenter
        let names = [
            NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification,
        ]
        volumeObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.coordinator.volumesChanged()
                    self?.saveDiskDetails()
                }
            }
        }
    }

    func stop() {
        volumeObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        volumeObservers = []
        coordinator.stop()
    }

    /// Keeps the details of each indexed disk that is plugged in, to show them while it is not.
    private func saveDiskDetails() {
        for root in roots() {
            let url = URL(fileURLWithPath: root.path)
            guard (try? url.resourceValues(forKeys: [.volumeURLKey]))?.volume?.standardizedFileURL.path == root.path,
                  let details = DiskDetails.of(volume: url), details != root.diskDetails else { continue }
            try? store.setDetails(root.id, JSONEncoder().encode(details))
        }
    }

    func roots() -> [IndexRoot] {
        (try? store.roots()) ?? []
    }

    func summary(of root: IndexRoot) -> (items: Int64, totalSize: Int64) {
        (try? store.summary(of: root)) ?? (0, 0)
    }

    func addRoot(path: String, exclusions: [String]) {
        coordinator.addRoot(path: path, exclusions: exclusions)
    }

    func removeRoot(_ id: Int64) {
        coordinator.removeRoot(id)
    }

    func setExclusions(_ id: Int64, _ exclusions: [String]) {
        coordinator.setExclusions(id, exclusions)
    }

    func rebuild(_ id: Int64) {
        coordinator.rebuild(id)
    }

    /// Total sizes of the items in the folder at `path` (canonical), by name.
    func sizes(ofFolder path: String) -> [String: Int64] {
        (try? store.childSizes(ofFolder: path)) ?? [:]
    }
}

extension IndexService {
    /// The items of a folder on a disk that is not plugged in, from the catalog, and the
    /// disk's name. Nil when the folder's disk is there (or the folder is not indexed).
    func catalog(ofFolder path: String) -> (entries: [DirectoryEntry], disk: String)? {
        guard let root = try? store.root(containing: path), !root.isAvailable,
              let entries = try? store.catalogEntries(ofFolder: path) else { return nil }
        return (entries, root.diskName)
    }

    /// Cataloged disks that are not plugged in.
    func offlineDisks() -> [IndexRoot] {
        roots().filter { $0.volumeID != nil && $0.path != "/" && !$0.isAvailable }
    }

    /// The catalog entry of the volume mounted at `path`, if it is cataloged.
    func catalogRoot(at path: String) -> IndexRoot? {
        roots().first { $0.path == FolderWatcher.canonicalPath(of: URL(fileURLWithPath: path)) }
    }

    /// Indexes a disk, keeping it in the catalog while it is unplugged.
    func addToCatalog(_ url: URL) {
        let path = FolderWatcher.canonicalPath(of: url)
        addRoot(path: path, exclusions: path == "/" ? Self.defaultExclusions : [])
    }

    /// Runs `query` off the main thread.
    func search(_ query: SearchQuery) async -> [SearchResult] {
        let store = store
        return await Task.detached(priority: .userInitiated) { (try? store.search(query)) ?? [] }.value
    }

    /// Finder tags in the index, most used first.
    func tagNames() -> [String] {
        ((try? store.tagCounts()) ?? []).map(\.name)
    }
}

extension IndexRoot {
    /// The disk's saved details, if any.
    var diskDetails: DiskDetails? {
        details.flatMap { try? JSONDecoder().decode(DiskDetails.self, from: $0) }
    }

    /// The disk's name as last seen, else the root folder's name.
    var diskName: String {
        diskDetails?.name ?? FileManager.default.displayName(atPath: path)
    }
}
