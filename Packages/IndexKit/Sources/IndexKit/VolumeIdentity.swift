import Foundation

/// A mounted volume: its mount point and stable UUID.
public struct MountedVolume: Equatable, Sendable {
    public let path: String
    public let uuid: String

    public init(path: String, uuid: String) {
        self.path = path
        self.uuid = uuid
    }

    public static func current() -> [MountedVolume] {
        (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeUUIDStringKey]) ?? [])
            .compactMap { url in
                (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString).map {
                    MountedVolume(path: url.path, uuid: $0)
                }
            }
    }
}

public extension IndexRoot {
    /// The root's folder is there, and for a volume root, it is the same disk (another disk
    /// mounted under the same name is not).
    var isAvailable: Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        guard let volumeID else { return true }
        let uuid = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        return uuid == volumeID
    }
}

public extension IndexStore {
    /// Volume roots get their volume UUID; a disk mounted at another path than before (a
    /// rename, a name clash) moves its root there. Returns the roots that changed.
    @discardableResult
    func updateVolumes(_ mounted: [MountedVolume] = MountedVolume.current()) throws -> [Int64] {
        var changed: [Int64] = []
        for root in try roots() {
            let update: MountedVolume? = if let volumeID = root.volumeID {
                mounted.first { $0.uuid == volumeID && $0.path != root.path && !root.isAvailable }
            } else {
                mounted.first { $0.path == root.path }
            }
            guard let update, (try? setVolume(root.id, path: update.path, volumeID: update.uuid)) != nil else {
                continue
            }
            changed.append(root.id)
        }
        return changed
    }
}
