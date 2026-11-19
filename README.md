# Arbor

A native macOS file manager on an infinite canvas.

Every folder you open becomes a **panel** on the canvas, connected by a curved
**branch** to the folder you opened it from. You see all your folders at once, with the
full path that leads to each one. An internal index makes folder sizes instant, search
immediate, and keeps external disks browsable and searchable even when they are
unplugged.

> **Status:** early development. The repository is bootstrapped; features land phase by
> phase as described in [ROADMAP.md](ROADMAP.md).

- macOS 14 or later, Apple Silicon and Intel
- No network access, no telemetry
- Open source, MIT license

## Install

1. Download `Arbor-x.y.z.dmg` (or `.zip`) from
   [GitHub Releases](../../releases).
2. Optionally verify the download against `SHA256SUMS.txt`:
   ```bash
   shasum -a 256 -c SHA256SUMS.txt --ignore-missing
   ```
3. Drag **Arbor** to **Applications**.

### Opening Arbor the first time (macOS 15 and later)

Arbor is signed with a self-signed certificate, not with an Apple Developer ID, and is
not notarized. Gatekeeper therefore blocks the first launch. On macOS 15 and later the
old Control-click › Open shortcut no longer bypasses this. Instead:

1. Open Arbor once. macOS says it cannot verify the app. Click **Done**.
2. Open **System Settings › Privacy & Security**, scroll to **Security**, and click
   **Open Anyway** next to the message about Arbor. The button appears for about an
   hour after the blocked attempt.
3. Confirm with **Open Anyway** and authenticate.

Alternatively, remove the quarantine attribute in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/Arbor.app
```

You only need to do this once per downloaded version.

### Granting Full Disk Access

Arbor works without extra permissions, but macOS then hides some locations (Mail,
Safari, other apps' containers, some system folders) and asks for access folder by
folder. For a complete index and folder sizes, grant Full Disk Access:

1. Open **System Settings › Privacy & Security › Full Disk Access**.
2. Click **+**, choose **Arbor** in Applications, and turn the switch on.
3. Quit and reopen Arbor.

Every release is signed with the same certificate, so **Full Disk Access persists across
updates**. If it is ever lost (for example after a certificate rotation, announced in the
release notes), Arbor detects it at launch, keeps working in a limited mode, and guides
you through granting it again.

## Build from source

Requirements: Xcode 16 or later, [Homebrew](https://brew.sh).

```bash
brew install xcodegen swiftlint swiftformat
```

```bash
git config core.hooksPath .githooks
```

```bash
xcodegen generate && open Arbor.xcodeproj
```

Run a module's tests without the app:

```bash
swift test --package-path Packages/IndexKit
```

Local builds are ad hoc signed, so macOS forgets Full Disk Access each time you rebuild.
Release signing setup is described in [docs/signing.md](docs/signing.md).

## License

[MIT](LICENSE)
