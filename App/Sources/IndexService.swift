import Foundation
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

    /// UI tests index only their fixture folder, in a database next to it.
    static func openForUITests(fixture: URL) throws -> IndexService {
        let store = try IndexStore.open(at: fixture.deletingLastPathComponent().appendingPathComponent("index.sqlite"))
        _ = try store.addRoot(path: FolderWatcher.canonicalPath(of: fixture), exclusions: [])
        return IndexService(store: store)
    }

    func start() {
        coordinator.start()
    }

    func stop() {
        coordinator.stop()
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
