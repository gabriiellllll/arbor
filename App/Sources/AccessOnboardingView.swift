import AppKit
import SwiftUI

@MainActor
extension FullDiskAccess {
    /// Opens System Settings › Privacy & Security › Full Disk Access.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// Explains Full Disk Access and how to grant it, first run or after it was lost.
struct AccessOnboardingView: View {
    let prompt: AccessOnboarding.Prompt
    let continueLimited: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: prompt == .lost ? "lock.trianglebadge.exclamationmark" : "lock.open")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            // swiftlint:disable line_length
            if prompt == .lost {
                Text("Full Disk Access Was Turned Off").font(.title2.bold())
                Text(
                    "Arbor had Full Disk Access before, but macOS no longer grants it. This can happen after an update signed with a new certificate or if the switch was turned off."
                )
            } else {
                Text("Give Arbor Full Disk Access").font(.title2.bold())
                Text(
                    "Arbor reads folders and sizes across your disks. Without Full Disk Access, macOS hides some locations and Arbor works in a limited mode."
                )
            }
            // swiftlint:enable line_length
            VStack(alignment: .leading, spacing: 8) {
                Label("Open System Settings › Privacy & Security › Full Disk Access.", systemImage: "1.circle")
                Label("Turn on Arbor (click + to add it if it is not listed).", systemImage: "2.circle")
                Label("Quit and reopen Arbor.", systemImage: "3.circle")
            }
            HStack {
                Spacer()
                Button("Continue in Limited Mode", action: continueLimited)
                Button("Open System Settings") { FullDiskAccess.openSettings() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(24)
        .frame(width: 480)
    }
}

/// Shown above the canvas while Arbor runs without Full Disk Access.
struct LimitedModeBanner: View {
    static let height: CGFloat = 32

    var body: some View {
        HStack {
            Image(systemName: "lock")
            Text("Limited mode: without Full Disk Access, some folders can’t be read.")
            Spacer()
            Button("Grant Access…") { FullDiskAccess.openSettings() }
                .controlSize(.small)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(Color.yellow.opacity(0.15))
    }
}
