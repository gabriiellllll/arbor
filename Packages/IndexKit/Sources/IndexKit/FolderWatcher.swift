import CoreServices
import Foundation

/// A directory reported as changed by FSEvents.
public struct FolderChange: Hashable, Sendable {
    public let path: String
    /// Events were lost (dropped, history wrapped, watched root moved): everything below
    /// `path` must be rescanned.
    public let mustRescanSubfolders: Bool
    /// FSEvents event ID, to resume from after a relaunch (0 when unknown).
    public let eventID: UInt64

    public init(path: String, mustRescanSubfolders: Bool, eventID: UInt64 = 0) {
        self.path = path
        self.mustRescanSubfolders = mustRescanSubfolders
        self.eventID = eventID
    }
}

/// Watches directory trees with FSEvents and reports which directories changed.
/// Changes anywhere below a watched path are reported with the directory that changed.
public final class FolderWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([FolderChange]) -> Void

    /// Owned by the stream (retained through the context), so callbacks never reach a
    /// deallocated watcher.
    private final class Callback: Sendable {
        let handler: Handler

        init(_ handler: @escaping Handler) {
            self.handler = handler
        }
    }

    private let queue = DispatchQueue(label: "app.arbor.FolderWatcher")
    private let latency: TimeInterval
    private let callback: Callback
    /// Accessed only on `queue` (and in `deinit`).
    private var stream: FSEventStreamRef?

    public init(latency: TimeInterval = 0.2, handler: @escaping Handler) {
        self.latency = latency
        callback = Callback(handler)
    }

    deinit {
        stopStream()
    }

    /// Replaces the set of watched paths. An empty set stops watching. With `since`, changes
    /// made after that event ID (even while the app was not running) are reported first.
    public func watch(_ paths: Set<String>, since eventID: UInt64? = nil) {
        queue.sync {
            stopStream()
            guard !paths.isEmpty else { return }
            startStream(paths: Array(paths), since: eventID)
        }
    }

    /// The latest FSEvents event ID: record it before a scan, and resume from it.
    public static var currentEventID: UInt64 {
        FSEventsGetCurrentEventId()
    }

    /// Identifies the FSEvents history of the volume holding `path`. Event IDs only make
    /// sense for the same history: if it changes, the index must be rebuilt.
    public static func volumeUUID(for path: String) -> String? {
        var info = stat()
        guard stat(path, &info) == 0, let uuid = FSEventsCopyUUIDForDevice(info.st_dev) else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// The path FSEvents reports for `url`: symlinks resolved, including `/var` → `/private/var`
    /// (which `URL.resolvingSymlinksInPath()` deliberately does not do). Compare reported
    /// changes against this. A missing item (an unplugged disk's folder) resolves through its
    /// closest existing parent.
    public static func canonicalPath(of url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else {
            let parent = url.deletingLastPathComponent()
            guard url.path != "/", parent.path != url.path else { return normalized(url.path) }
            return (canonicalPath(of: parent) as NSString).appendingPathComponent(url.lastPathComponent)
        }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func startStream(paths: [String], since eventID: UInt64?) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(callback).toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<Callback>.fromOpaque(info).retain()
                return info
            },
            release: { info in
                guard let info else { return }
                Unmanaged<Callback>.fromOpaque(info).release()
            },
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        guard let stream = FSEventStreamCreate(
            nil, FolderWatcher.streamCallback, &context, paths as CFArray,
            eventID ?? FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
        ) else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    private func stopStream() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private static let streamCallback: FSEventStreamCallback = { _, info, count, paths, flags, ids in
        guard let info else { return }
        let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
        let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let historyDone = FSEventStreamEventFlags(kFSEventStreamEventFlagHistoryDone)
        let rescan = FSEventStreamEventFlags(
            kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagEventIdsWrapped
                | kFSEventStreamEventFlagRootChanged
        )
        let changes = (0 ..< count).compactMap { index -> FolderChange? in
            // The marker ending the replay of past events is not a change.
            guard flags[index] & historyDone == 0 else { return nil }
            return FolderChange(
                path: normalized(String(cString: cPaths[index])),
                mustRescanSubfolders: flags[index] & rescan != 0,
                eventID: ids[index]
            )
        }
        if !changes.isEmpty {
            callback.handler(changes)
        }
    }
}
