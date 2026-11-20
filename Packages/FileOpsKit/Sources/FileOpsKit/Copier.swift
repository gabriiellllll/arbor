import Darwin
import Foundation

/// Copies one item (file or folder tree) with `copyfile(3)`: data, metadata, extended
/// attributes (Finder tags) and ACLs; clones on APFS when allowed. Reports copied bytes and
/// honors pause and cancel between chunks.
struct Copier {
    let allowsClone: Bool

    enum Failure: Error {
        case cancelled
        case system(Int32)
    }

    private final class Context {
        let control: OperationControl
        let onBytes: (Int64) -> Void
        var finished: Int64 = 0
        var current: Int64 = 0

        init(control: OperationControl, onBytes: @escaping (Int64) -> Void) {
            self.control = control
            self.onBytes = onBytes
        }
    }

    /// `onBytes` receives the total bytes copied so far for this item.
    func copy(_ source: URL, to destination: URL, control: OperationControl,
              onBytes: @escaping (Int64) -> Void) throws
    {
        // Never write over (or later clean up) an item that already exists: conflicts are
        // resolved before copying.
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw Failure.system(EEXIST) }
        let context = Context(control: control, onBytes: onBytes)
        guard let state = copyfile_state_alloc() else { throw Failure.system(ENOMEM) }
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { what, stage, state, _, _, info in
            guard let info else { return COPYFILE_CONTINUE }
            let context = Unmanaged<Context>.fromOpaque(info).takeUnretainedValue()
            if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                context.current = Int64(copied)
                context.onBytes(context.finished + context.current)
            } else if what == COPYFILE_RECURSE_FILE, stage == COPYFILE_FINISH {
                context.finished += context.current
                context.current = 0
            }
            return context.control.proceed() ? COPYFILE_CONTINUE : COPYFILE_QUIT
        }
        let info = Unmanaged.passUnretained(context).toOpaque()
        withExtendedLifetime(context) {
            copyfile_state_set(
                state,
                UInt32(COPYFILE_STATE_STATUS_CB),
                unsafeBitCast(callback, to: UnsafeRawPointer.self)
            )
            copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), info)
        }
        var flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_EXCL)
        if allowsClone {
            flags |= copyfile_flags_t(COPYFILE_CLONE)
        }
        let status = withExtendedLifetime(context) { copyfile(source.path, destination.path, state, flags) }
        if status != 0 {
            let error = errno
            // The destination did not exist before: whatever is there is an incomplete copy.
            try? FileManager.default.removeItem(at: destination)
            throw control.isCancelled || error == ECANCELED ? Failure.cancelled : Failure.system(error)
        }
    }
}
