import Foundation

/// One item of a directory listing.
public struct DirectoryEntry: Equatable, Sendable {
    public enum Kind: Sendable {
        case file, directory, symlink, other
    }

    public let name: String
    public let kind: Kind
    /// Logical size in bytes (all forks). Zero for directories.
    public let size: Int64
    /// Bytes allocated on disk. Zero for directories.
    public let allocatedSize: Int64
    /// Number of entries, for directories only.
    public let itemCount: Int?
    public let created: Date
    public let modified: Date
    /// Inode number, unique per volume.
    public let fileID: UInt64
    /// Hidden by a leading dot or the `UF_HIDDEN` flag.
    public let isHidden: Bool
    /// Another volume is mounted here (scans don't cross into it).
    public let isMountPoint: Bool

    public init(
        name: String, kind: Kind, size: Int64, allocatedSize: Int64, itemCount: Int?,
        created: Date, modified: Date, fileID: UInt64, isHidden: Bool, isMountPoint: Bool = false
    ) {
        self.name = name
        self.kind = kind
        self.size = size
        self.allocatedSize = allocatedSize
        self.itemCount = itemCount
        self.created = created
        self.modified = modified
        self.fileID = fileID
        self.isHidden = isHidden
        self.isMountPoint = isMountPoint
    }
}
