import Foundation

/// A mounted volume, as shown in the sidebar.
public struct Volume: Equatable, Sendable {
    public let url: URL
    public let name: String
    public let isRoot: Bool
    public let isRemovable: Bool
    public let isInternal: Bool
    /// The network share mounted here (`smb://server/share`), nil for a local disk.
    public var remountURL: URL?

    public init(
        url: URL, name: String, isRoot: Bool = false, isRemovable: Bool = false, isInternal: Bool = false,
        remountURL: URL? = nil
    ) {
        self.url = url
        self.name = name
        self.isRoot = isRoot
        self.isRemovable = isRemovable
        self.isInternal = isInternal
        self.remountURL = remountURL
    }

    public var isNetwork: Bool {
        remountURL != nil
    }
}

/// Volumes currently mounted and visible to the user (hidden system volumes skipped).
public enum MountedVolumes {
    public static func current() -> [Volume] {
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeIsRootFileSystemKey, .volumeIsRemovableKey, .volumeIsInternalKey,
            .volumeIsLocalKey, .volumeURLForRemountingKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []
        return ordered(urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return Volume(
                url: url,
                name: values.volumeName ?? url.lastPathComponent,
                isRoot: values.volumeIsRootFileSystem ?? false,
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? false,
                remountURL: values.volumeIsLocal == false ? values.volumeURLForRemounting : nil
            )
        })
    }

    /// The startup volume first, then by name.
    static func ordered(_ volumes: [Volume]) -> [Volume] {
        volumes.sorted { lhs, rhs in
            if lhs.isRoot != rhs.isRoot {
                return lhs.isRoot
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
