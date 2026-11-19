# Roadmap

Each phase ships as one branch and one PR (green CI, this file updated). Items are checked
when merged-ready: implemented, tested, documented.

## Phase 0 — Bootstrap
- [x] `commit-msg` hook (Conventional Commits, no attribution mentions)
- [x] Git ignore rules, MIT license, SwiftLint / SwiftFormat configs
- [x] Project guide and roadmap
- [x] Six Kit packages scaffolded, each with a passing test
- [x] XcodeGen app shell with unit test and launch UI test
- [x] CI workflow (Kit test matrix, app build + test, lint, commit check, `.xcresult` upload)
- [x] Release workflow (protected environment, temporary keychain, self-signed, zip + dmg + SHA-256)
- [x] README (install, Gatekeeper, Full Disk Access) and signing setup guide

## Phase 1 — Canvas and panels
- [x] Viewport model: pan, zoom around a point, zoom limits, reset (tested)
- [x] Canvas view: trackpad pan, space + drag, hand tool, pinch, ⌘+ / ⌘-, zoom % in toolbar, reset button
- [x] Canvas backgrounds: dots, grid, crosses, plain
- [x] Main window: left sidebar, canvas, collapsible right inspector
- [x] `getattrlistbulk` directory reader (tested on temporary trees)
- [x] Folder panel: title bar (icon, name, item count), sortable Name / Size / Modified columns
- [x] Panel resize and drag; list mode and icon mode
- [x] Panel tree model: open child, replace sibling branch, ⌘-click multiple branches (tested)
- [x] Bézier branch from the clicked row to the child panel; source row stays highlighted
- [x] Deep navigation: visible panel chain, auto-scroll to the active panel
- [x] Live folder updates via FSEvents
- [x] Full Disk Access detection, onboarding, degraded mode
- [x] UI tests: launch, open a folder, create a child panel

## Phase 2 — Layouts and colors
- [x] Layouts: tree right, tree down, star, manual (deterministic, tested)
- [x] Overlap removal in automatic layouts (tested)
- [x] Animated layout changes with attached branches
- [x] Per-branch colors (one per root, from its sidebar place), inherited by sub-branches; editable favorite colors come with phase 3 favorites
- [x] Side-by-side comparison of sibling folders: homologous folders on the same row, mirrored navigation, one-sided items marked

## Phase 3 — Sidebar, workspaces, basic operations
- [ ] Workspaces: create, rename, delete, each remembers its canvas
- [ ] Shared section (scope to confirm)
- [ ] Favorites: drag and drop, color, remove
- [ ] Locations: volumes, iCloud Drive, OneDrive if present, Computer
- [ ] Finder tags: read and write
- [ ] File operation queue: progress, pause, cancel, conflicts (replace, keep both, skip, apply to all) (tested)
- [ ] Drag and drop between panels and with Finder (move, ⌥ copy)
- [ ] Multi-selection across panels: copy, move, rename, trash
- [ ] Undo / redo of file operations (tested)
- [ ] Canvas navigation history

## Phase 4 — Internal index
- [ ] Parallel per-volume scan with `getattrlistbulk` into SQLite (tested)
- [ ] Aggregated folder sizes propagated to parents (tested)
- [ ] Incremental FSEvents updates with persisted event ID, catch-up, targeted rescan on `MustScanSubDirs` (tested with simulated events)
- [ ] Size view: sort and proportional bar behind each row
- [ ] Settings: indexed volumes, exclusions, index status, rebuild

## Phase 5 — Search
- [ ] Instant name search (FTS5 + prefixes)
- [ ] Full-text extraction: PDF, .docx / .xlsx / .pptx, plain text / Markdown / code (background, low priority)
- [ ] Search results as a canvas panel, each result can open its parent chain
- [ ] Filters: type, size, date, tag, volume

## Phase 6 — External disks and shares
- [ ] Stable volume identity (volume UUID, DiskArbitration)
- [ ] Offline catalog: browse and search unplugged disks, "plug in disk X" hint
- [ ] Disk details: vendor, model, serial, connection type, capacity, file system (IOKit)
- [ ] User chooses which disks join the catalog
- [ ] Network shares (SMB / AFP / NFS): remembered, one-click reconnect (NetFS), Keychain credentials

## Phase 7 — Batch rename and merge
- [ ] Rename engine: find/replace (regex, case), prefix/suffix, numbering, dates (created, modified, EXIF), case change (tested)
- [ ] Rename sheet with live preview and collision detection, across folders
- [ ] Undoable execution
- [ ] Merge same-name folders with conflict report and per-file choice

## Phase 8 — Gallery and previews
- [ ] QuickLook thumbnails with disk cache
- [ ] Grid mode per panel
- [ ] Pinnable gallery in the inspector
- [ ] Quick Look on space bar
- [ ] Batch image conversion and resize (JPEG, HEIC, PNG; WebP export needs a decision: ImageIO cannot encode it)

## Phase 9 — Backup and versions
- [ ] Deduplicated content-addressed chunk store (SHA-256) (tested)
- [ ] Browse versions and one-click restore
- [ ] Optional AES-GCM encryption, scrypt key derivation, one-time recovery key (tested)
- [ ] Scheduling and retention policy

## Phase 10 — Polish
- [ ] Full toolbar
- [ ] Complete keyboard shortcuts and 100 % keyboard navigation
- [ ] VoiceOver, light and dark mode
- [ ] State restoration on relaunch (workspaces, canvas, zoom)
- [ ] Performance: 60 fps with 30 panels; 100 000-item folder opens in < 300 ms (measured)
