import Foundation
import NetFS

/// Mounts network shares (SMB, AFP, NFS, WebDAV) through NetFS.
public enum NetworkShares {
    /// Mounts `url` and returns its mount points. With `allowUI`, macOS shows its own sign-in
    /// window (which can save the password in the Keychain, and reuses it next time) and, for a
    /// server URL without a share, its own share picker. Arbor never sees the password.
    public static func mount(_ url: URL, allowUI: Bool = true) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            let options = NSMutableDictionary()
            options[kNAUIOptionKey] = allowUI ? kNAUIOptionAllowUI : kNAUIOptionNoUI
            var request: AsyncRequestID?
            let status = NetFSMountURLAsync(
                url as CFURL, nil, nil, nil, options as CFMutableDictionary, nil, &request, .main
            ) { status, _, mountpoints in
                if status == 0 || status == EEXIST {
                    let paths = (mountpoints as? [String]) ?? []
                    continuation.resume(returning: paths.map { URL(fileURLWithPath: $0, isDirectory: true) })
                } else {
                    continuation.resume(throwing: error(status))
                }
            }
            // Mount errors come through the block; a non-zero status here means the request never started.
            if status != 0 {
                continuation.resume(throwing: error(status))
            }
        }
    }

    /// The URL of a server address typed by the user: `nas.local/Media` means SMB.
    public static func url(from address: String) -> URL? {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: address.contains("://") ? address : "smb://\(address)")
        return url?.host?.isEmpty == false ? url : nil
    }

    /// Whether `error` means the user cancelled the sign-in or share picker.
    public static func isCancellation(_ error: any Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSPOSIXErrorDomain && error.code == Int(ECANCELED))
            || (error.domain == NSOSStatusErrorDomain && error.code == userCanceledErr)
    }

    /// NetFS returns errno values (positive) or NetFS/OSStatus codes (negative).
    static func error(_ status: Int32) -> NSError {
        NSError(domain: status > 0 ? NSPOSIXErrorDomain : NSOSStatusErrorDomain, code: Int(status))
    }
}
