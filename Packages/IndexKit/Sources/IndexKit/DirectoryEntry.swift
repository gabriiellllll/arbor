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
}
