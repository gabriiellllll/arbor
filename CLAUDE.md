# Arbor

Native macOS file manager on an infinite canvas. Each opened folder is a **panel** on the
canvas, linked by a curved **branch** to the parent panel it was opened from. An internal
index (SQLite) makes folder sizes instant, search immediate, and keeps offline catalogs of
external disks. Roadmap and status: `ROADMAP.md`.

## Language
- Everything in the repository is in **English**: code, identifiers, comments, commit
  messages, branch names, PRs, issues, docs, test names, log and error messages.
- UI base language is English. Every user-facing string goes through
  `App/Resources/Localizable.xcstrings` (`String(localized:)`, `LocalizedStringResource`).
  Never hard-code a user-facing string.
- The maintainer is addressed in French in interactive sessions; the repo stays English.

## Constraints
- Swift 6 (language mode 6, strict concurrency), `swift-tools-version: 6.0`.
  CI runs `macos-15` with stable Xcode (Swift 6.1): do not use newer language/SDK APIs.
- Deployment target macOS 14. Universal binary (arm64 + x86_64) for releases.
- AppKit for canvas, panels and lists (NSTableView/NSOutlineView, CAShapeLayer branches).
  SwiftUI only for settings, modal sheets and the inspector.
- Not sandboxed. No network access, no telemetry, ever.
- Only external dependency: **GRDB** (SQLite, FTS5). Adding any other dependency needs
  the maintainer's approval.
- Never fake a feature. If a system API blocks something, say so and propose an alternative.

## Layout
```
project.yml            XcodeGen spec (the .xcodeproj is generated, never committed)
App/Sources            App target: windows, sidebar, inspector, onboarding, app database
App/Resources          Localizable.xcstrings, assets
App/Tests              App unit tests (XCTest)
App/UITests            Minimal XCUITests (launch, open folder, child panel)
Packages/<Kit>         One local SwiftPM package per module, each testable with `swift test`
.githooks/commit-msg   Commit message policy (also run by CI)
.github/workflows      ci.yml (push/PR), release.yml (tags v*)
scripts/               Release packaging and helpers
docs/                  Maintainer docs (signing setup)
```

## Modules
| Kit | Responsibility | Depends on |
|-----|----------------|------------|
| CanvasKit | Viewport math (pan/zoom), layouts (tree right/down, star, manual), overlap removal, branch Bézier geometry, Codable canvas model, AppKit canvas/panel host/branch layer views. Knows nothing about files. | — |
| IndexKit | `getattrlistbulk` directory reader and scanner, GRDB index store, aggregated folder sizes, FSEvents watcher with persisted event IDs, FTS5 name + content search, text extraction. | GRDB |
| FileOpsKit | File operation queue (progress, pause, cancel, conflicts), undo/redo, batch rename engine, folder merge, Finder tags. | — |
| DiskKit | Volume identity (UUID, DiskArbitration), IOKit disk details, offline catalog, network shares (NetFS) with Keychain credentials. | IndexKit (from phase 6) |
| PreviewKit | QuickLookThumbnailing with disk cache, batch image conversion (ImageIO). | — |
| BackupKit | Content-addressed chunk store (SHA-256), versions/restore, AES-GCM, scrypt, recovery key, retention. | — |

Rules: business logic lives in Kits and is testable without UI. A Kit only depends on
another Kit when there is a concrete need. UI types are `@MainActor`; shared mutable
state lives in actors. Mark deliberate simplifications with a `// ponytail:` comment
naming the limit and the upgrade path.

## Commands
```bash
# One-time setup after cloning
brew install xcodegen swiftlint swiftformat
git config core.hooksPath .githooks

# Kit tests (repeat per Kit)
swift test --package-path Packages/CanvasKit

# App: generate project, build and test
xcodegen generate
xcodebuild -project Arbor.xcodeproj -scheme Arbor -destination 'platform=macOS' build test

# Lint and format
swiftlint --strict
swiftformat --lint .
swiftformat .            # apply formatting
```
Local Debug builds are ad hoc signed, so macOS forgets Full Disk Access on every rebuild.
Release builds use the stable self-signed certificate (see `docs/signing.md`).

## Git
- Commits use the repository's configured git identity. Never change `user.name` /
  `user.email`, never pass `--author`.
- No mention of Claude, AI or Anthropic anywhere (commits, PRs, code, docs): no
  `Co-Authored-By`, no `Claude-Session`, no "Generated with". The hook enforces it.
- Conventional Commits, English, scope = module: `feat(canvas): …`, `fix(index): …`,
  `test(rename): …`, `refactor`, `chore`, `ci`, `docs`, `build`.
- **Micro-commits**: one logical change per commit, ideally < 150 changed lines
  (excluding generated files). Commit as soon as a step builds and its tests pass.
  Never commit a broken build or failing tests.
- `main` is always green. One branch per phase or sub-feature (`feat/phase-1-canvas`).
  Push regularly.
- End of phase: `gh pr create`, then `gh pr checks --watch` until green, update
  `ROADMAP.md`, stop and report. The maintainer reviews and merges (rebase merge).
  Never merge yourself.
- Never commit the generated `.xcodeproj`, DerivedData, `.p12`/keys or any secret.

## Tests
- TDD for IndexKit, FileOpsKit and the rename logic: tests with or before the code.
- Integration tests only touch temporary directories (`FileManager.default.temporaryDirectory`
  + UUID), never real user files.
- Priorities: index scan on generated trees, size propagation, simulated FSEvents
  catch-up; file ops (conflicts, undo); rename preview (regex, numbering, collisions);
  canvas layouts (deterministic positions, no overlap); backup (encryption round trip,
  recovery key, dedup).
- Coverage target ≥ 70 % per Kit.
- Never disable, delete or weaken a test to make CI pass: fix the code or report the issue.

## Release
`release.yml` runs on `v*` tags in the protected `release` environment: imports the
signing certificate into a temporary keychain (deleted at the end of the job), builds a
universal Release, signs it, produces `.zip` + `.dmg` + SHA-256 sums, and publishes a
GitHub Release with notes generated from commits. Setup: `docs/signing.md`.
