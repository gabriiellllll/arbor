import Darwin
import Foundation

/// Lists a directory with `getattrlistbulk(2)`: one system call returns the attributes of
/// many entries, far faster than `FileManager` enumeration plus per-file `stat`.
public enum DirectoryReader {
    private static let bufferSize = 256 * 1024

    public static func entries(at url: URL) throws -> [DirectoryEntry] {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }

        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = group(
            ATTR_CMN_RETURNED_ATTRS, ATTR_CMN_NAME, ATTR_CMN_ERROR, ATTR_CMN_OBJTYPE, ATTR_CMN_CRTIME,
            ATTR_CMN_MODTIME, ATTR_CMN_FLAGS, ATTR_CMN_FILEID
        )
        request.dirattr = group(ATTR_DIR_ENTRYCOUNT, ATTR_DIR_MOUNTSTATUS)
        request.fileattr = group(ATTR_FILE_TOTALSIZE, ATTR_FILE_ALLOCSIZE)

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferSize, alignment: 8)
        defer { buffer.deallocate() }

        var entries: [DirectoryEntry] = []
        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, bufferSize, UInt64(FSOPT_PACK_INVAL_ATTRS))
            if count < 0 {
                throw posixError()
            }
            if count == 0 {
                return entries
            }
            var record = buffer
            for _ in 0 ..< count {
                let length = record.loadUnaligned(as: UInt32.self)
                if let entry = parse(record) {
                    entries.append(entry)
                }
                record += Int(length)
            }
        }
    }

    /// Parses one record. With `FSOPT_PACK_INVAL_ATTRS` every requested common attribute is
    /// present, in kernel order. Directory attributes are only packed for directories and file
    /// attributes only for files, as reported by the returned attribute set.
    private static func parse(_ record: UnsafeMutableRawPointer) -> DirectoryEntry? {
        var cursor = Cursor(pointer: record + MemoryLayout<UInt32>.size)
        let returned = cursor.read(attribute_set_t.self)
        // ponytail: entries the kernel cannot describe are skipped; surface them if users need to see them.
        guard cursor.read(UInt32.self) == 0 else { return nil }

        let nameField = cursor.pointer
        let nameRef = cursor.read(attrreference_t.self)
        let name = String(cString: (nameField + Int(nameRef.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
        let type = cursor.read(UInt32.self)
        let created = cursor.readDate()
        let modified = cursor.readDate()
        let flags = cursor.read(UInt32.self)
        let fileID = cursor.read(UInt64.self)
        let hasDirAttrs = returned.dirattr & group(ATTR_DIR_ENTRYCOUNT) != 0
        let entryCount = hasDirAttrs ? cursor.read(UInt32.self) : 0
        let mountStatus = hasDirAttrs ? cursor.read(UInt32.self) : 0
        let hasFileAttrs = returned.fileattr & group(ATTR_FILE_TOTALSIZE) != 0
        let totalSize = hasFileAttrs ? cursor.read(Int64.self) : 0
        let allocSize = hasFileAttrs ? cursor.read(Int64.self) : 0

        let kind: DirectoryEntry.Kind = switch type {
        case UInt32(VREG.rawValue): .file
        case UInt32(VDIR.rawValue): .directory
        case UInt32(VLNK.rawValue): .symlink
        default: .other
        }
        return DirectoryEntry(
            name: name,
            kind: kind,
            size: kind == .directory ? 0 : totalSize,
            allocatedSize: kind == .directory ? 0 : allocSize,
            itemCount: kind == .directory ? Int(entryCount) : nil,
            created: created,
            modified: modified,
            fileID: fileID,
            isHidden: name.hasPrefix(".") || flags & UInt32(UF_HIDDEN) != 0,
            isMountPoint: mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0
        )
    }

    /// Combines attribute bits; the SDK imports some as `Int32` and some as `UInt32`.
    private static func group(_ bits: any BinaryInteger...) -> attrgroup_t {
        bits.reduce(0) { $0 | attrgroup_t(truncatingIfNeeded: $1) }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

private struct Cursor {
    var pointer: UnsafeMutableRawPointer

    mutating func read<T>(_: T.Type) -> T {
        let value = pointer.loadUnaligned(as: T.self)
        pointer += MemoryLayout<T>.size
        return value
    }

    mutating func readDate() -> Date {
        let time = read(timespec.self)
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_nsec) / 1_000_000_000)
    }
}
