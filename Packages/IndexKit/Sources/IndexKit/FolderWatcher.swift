import CoreServices
import Foundation

/// A directory reported as changed by FSEvents.
public struct FolderChange: Hashable, Sendable {
    public let path: String
    /// The system dropped events: everything below `path` must be rescanned.
    public let mustRescanSubfolders: Bool
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

    /// Replaces the set of watched paths. An empty set stops watching.
    public func watch(_ paths: Set<String>) {
        queue.sync {
            stopStream()
            guard !paths.isEmpty else { return }
            startStream(paths: Array(paths))
        }
    }

    /// The path FSEvents reports for `url`: symlinks resolved, including `/var` → `/private/var`
    /// (which `URL.resolvingSymlinksInPath()` deliberately does not do). Compare reported
    /// changes against this.
    public static func canonicalPath(of url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return normalized(url.path) }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func startStream(paths: [String]) {
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
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        guard let stream = FSEventStreamCreate(
            nil, FolderWatcher.streamCallback, &context, paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags
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

    private static let streamCallback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let callback = Unmanaged<Callback>.fromOpaque(info).takeUnretainedValue()
        let cPaths = paths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
        let rescan = FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs)
        let changes = (0 ..< count).map { index in
            FolderChange(
                path: normalized(String(cString: cPaths[index])),
                mustRescanSubfolders: flags[index] & rescan != 0
            )
        }
        callback.handler(changes)
    }
}
