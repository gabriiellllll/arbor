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
Delivered in two pull requests: 3a (sidebar, workspaces, tags, history) and 3b (file operations).

- [x] Workspaces: create, rename, delete, each remembers its canvas (saved on switch and on quit)
- [x] Favorites: drag and drop (from panels or Finder, reorder), color, remove
- [x] Locations: volumes, iCloud Drive, OneDrive if present, Computer
- [x] Finder tags: read and write (row dots, context menu, inspector)
- [x] Canvas navigation history (Back ⌘[, Forward ⌘])
- [x] File operation queue: progress, pause, cancel, conflicts (replace, keep both, skip, stop, apply to all) (tested)
- [x] Drag and drop between panels and with Finder (move, ⌥ copy)
- [x] Multi-selection across panels: copy, paste, move here, rename, trash
- [x] Undo / redo of file operations (tested)
- Moved: the Shared section comes with network shares (phase 6); the clickable Tags section comes with search panels (phase 5)

## Phase 4 — Internal index
- [x] Parallel per-volume scan with `getattrlistbulk` into SQLite (tested; about 50 000 items per second, no mount point crossing, exclusions)
- [x] Aggregated folder sizes propagated to parents (tested), shown and sorted in panels
- [x] Incremental FSEvents updates with persisted event ID, catch-up, targeted rescan on `MustScanSubDirs` (tested with simulated events)
- [x] Size view: sort and proportional bar behind each row (View › Show Size Bars)
- [x] Settings: indexed volumes, exclusions, index status, rebuild
- Delivered in two pull requests: 4a (index engine, sizes in panels) and 4b (size view, settings). Finder tags are not indexed yet: reading them costs a system call per file; phase 5 decides with tag filters.

## Phase 5 — Search
- [x] Instant name search (FTS5 + prefixes)
- [x] Full-text extraction: PDF, .docx / .xlsx / .pptx, plain text / Markdown / code (background, low priority)
- [x] Search results as a canvas panel, each result can open its parent chain
- [x] Filters: type, size, date, tag, volume
- [x] Sidebar Tags section: clicking a tag opens a panel of the items carrying it

Phase 5a notes: Finder tags are read into the index in a background pass after each scan
and on every change. A result inside a hidden folder reveals its chain only down to the
last visible folder (panels hide hidden items).

Phase 5b notes: document text is read on a background-priority queue after each scan and
on every change, then searched after names, with an excerpt column in search panels. The
first 100,000 characters of each file are searchable; files over 100 MB are skipped. Office
support covers .docx body text, .xlsx shared strings and .pptx slides (no headers,
footnotes or speaker notes); RTF, Pages / Numbers / Keynote and legacy .doc / .xls are not
read.

## Phase 6 — External disks and shares
- [x] Stable volume identity (volume UUID, DiskArbitration)
- [x] Offline catalog: browse and search unplugged disks, "plug in disk X" hint
- [x] Disk details: vendor, model, serial, connection type, capacity, file system (IOKit)
- [x] User chooses which disks join the catalog
- [ ] Network shares (SMB / AFP / NFS): remembered, one-click reconnect (NetFS), Keychain credentials
- [ ] Sidebar Shared section: mounted network shares and servers seen on the network

Phase 6a notes: the catalog is the index. A disk joins it from its sidebar menu ("Add to
Catalog") or Settings › Index; nothing is added automatically. An unplugged disk keeps its
items: it stays in the sidebar (greyed), its folders open as greyed, read-only panels with a
"Plug in X" banner, and search finds its files. A disk is recognised by its volume UUID, so
it is found again under another mount path. A disk plugged back in is re-read in full,
keeping unchanged items (and their document text), because it may have changed on another
Mac. Disk details come from Disk Arbitration and the I/O Registry and are saved, so an
unplugged disk shows them too. Network shares (6b) are next.

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
