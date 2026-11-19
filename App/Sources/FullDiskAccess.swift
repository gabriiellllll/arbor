import Darwin
import Foundation

/// Detects Full Disk Access. There is no public API: the standard probe is opening the
/// user's TCC database, which only processes with Full Disk Access may read.
enum FullDiskAccess {
    enum Status: Equatable {
        case granted, denied, unknown
    }

    static let probePath = NSHomeDirectory() + "/Library/Application Support/com.apple.TCC/TCC.db"

    static func status(probing path: String = probePath) -> Status {
        let descriptor = open(path, O_RDONLY)
        if descriptor >= 0 {
            close(descriptor)
            return .granted
        }
        return errno == EPERM || errno == EACCES ? .denied : .unknown
    }
}

/// Decides whether to show the Full Disk Access onboarding.
struct AccessOnboarding {
    enum Prompt: Equatable {
        /// Nothing to show.
        case none
        /// Never granted: explain why it helps.
        case firstRun
        /// Was granted before and is gone (update with a new certificate, user toggle…).
        case lost
    }

    static let wasGrantedKey = "fullDiskAccess.wasGranted"
    static let dismissedKey = "fullDiskAccess.onboardingDismissed"

    let defaults: UserDefaults

    /// What to show for `status`, recording a grant so a later loss can be detected.
    func prompt(for status: FullDiskAccess.Status) -> Prompt {
        switch status {
        case .granted:
            defaults.set(true, forKey: Self.wasGrantedKey)
            defaults.set(false, forKey: Self.dismissedKey)
            return .none
        case .unknown:
            return .none
        case .denied:
            if defaults.bool(forKey: Self.wasGrantedKey) {
                return defaults.bool(forKey: Self.dismissedKey) ? .none : .lost
            }
            return defaults.bool(forKey: Self.dismissedKey) ? .none : .firstRun
        }
    }

    /// The user chose to continue in limited mode.
    func dismiss() {
        defaults.set(true, forKey: Self.dismissedKey)
    }
}
