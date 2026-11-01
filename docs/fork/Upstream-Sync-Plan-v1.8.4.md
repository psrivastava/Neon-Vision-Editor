# Upstream Sync Plan — fork/integration → upstream v1.8.4

_Analysis date: 2026-09-26. Author: sync analysis pass._

## TL;DR

Do **not** merge 1,493 upstream commits into `fork/integration`. The fork's unique value is
**8 commits** on top of merge-base `402e0e5f` (2026-07-23). Upstream has since re-architected the
exact editor subsystems the fork's *non-additive* edits touch. The clean path is to **rebuild the
fork on top of `upstream/main` as a fresh branch**, re-applying fork work in layers, keeping the
additive parts verbatim and re-evaluating the shared-file edits against upstream's new architecture.

## Divergence facts

| Fact | Value |
|------|-------|
| Merge base | `402e0e5f` (2026-07-23) |
| Fork-unique commits | 8 (non-merge) |
| Upstream commits ahead | 1,493 (~474 pure automation/docs) |
| Version gap | v0.9.6 → v1.8.4 |
| Repo layout | moved to `Project/Sources/` + `Project/Tests/`; Xcode-16 synchronized folder groups (`PBXFileSystemSynchronized`) |
| Trial merge conflicts | 19 (rename-plus-content across the move) |

## The 8 fork commits, categorized

### A. Purely additive — carry over verbatim (new `Fork/` folder upstream lacks)
- `3992ecfd` NotepadMac ports A+B — `Fork/StringTransforms.swift`, `LineEndings.swift`,
  `DocumentFormatter.swift`, `OpenLocation.swift` (+ tests)
- `760f5de8` Preview orientation + Vivid template — `Fork/MarkdownPreviewVivid.swift`,
  `PreviewOrientation.swift`
- `5de229c3` / `c6c54516` Design system — `Fork/DesignTokens.swift`, `ChromeStyle.swift`,
  `BreadcrumbBar.swift`, `CommandPalette.swift`, `CommandRegistry.swift`, `MenuCommands.swift`
- `3f8a5a51` UX polish (view-mode bar, chrome tokens)
- `d9e3adfd` **Tree-sitter engine** — `Fork/SyntaxEngine.swift`, `Fork/TreeSitterHighlighter.swift`
  + 11 SPM grammar deps in pbxproj. **Unique; upstream has no equivalent.**

### B. Shared-file edits — RE-EVALUATE against upstream's new architecture
These are the conflict hotspots, and several may be **superseded**:
- `Core/SyntaxHighlighting.swift` — upstream gutted it (−195 lines) and split out
  `HTMLSyntaxHighlighting.swift`. Fork's tree-sitter seam must be re-attached to the new shape.
- `UI/EditorTextView*.swift` — upstream added `VirtualEditorView+macOS.swift` (virtualized editor).
  Fork's `EditorTextView+RuntimePolicy.swift` large-file gating likely **superseded** by upstream's
  virtual editor + `FileBackedTextDocument`.
- `Data/EditorViewModel.swift`, `UI/ContentView*.swift`, `NeonSettingsView.swift`,
  `PanelsAndHelpers.swift`, `SidebarViews.swift`, `App/NeonVisionEditorApp.swift` — reconcile
  design-token migration + settings keys against upstream edits.

## Overlap: fork vs upstream solving the same problems
| Problem | Fork approach | Upstream approach | Resolution |
|---------|--------------|-------------------|------------|
| CSS-in-HTML highlighting | tree-sitter grammar | `HTMLSyntaxHighlighting.swift` bounded-chunk scanner (`8bf58a8f`) | Keep tree-sitter as the toggled engine; let upstream's scanner be the regex-path default |
| Large-file behavior | `RuntimePolicy` gating/throttle | virtual editor + file-backed document | Prefer upstream's architecture; drop/trim fork gating |
| Live theme refresh + syntax coverage | theme-derived highlights | `73dbd606` | Reconcile; likely keep fork tokens atop upstream refresh |

## Recommended strategy — layered rebuild on a safety branch

Branch: `sync/upstream-v1.8.4` off `upstream/main` (NOT off fork/integration). This never rewrites
the pushed `fork/integration`; it becomes the new integration tip only after it builds green.

**Phase 0 — prep.** Branch off upstream/main. Confirm build baseline (matrix script) on clean
upstream. Record upstream's `Project/Sources/` layout + synchronized-group behavior.

**Phase 1 — additive Fork/ folder.** Copy the entire `Fork/` folder + the 3 fork test files into
`Project/Sources/Neon Vision Editor/Fork/` and `Project/Tests/`. With synchronized folder groups
these auto-include — no pbxproj edits. Build.

**Phase 2 — tree-sitter SPM deps.** Re-wire the 11 grammar package refs + products into upstream's
pbxproj (the one required hand-edit; snapshot first). Resolve packages, build. Pin css=0.23.2 /
js=0.23.1 / python=0.23.6 (scanner.c manifest bug — see existing lesson).

**Phase 3 — syntax seam.** Re-attach the tree-sitter branch to upstream's refactored
`SyntaxHighlighting.swift` / `HTMLSyntaxHighlighting.swift`. Tree-sitter = toggled engine, upstream
scanner = regex default. Build + A/B.

**Phase 4 — design system + settings.** Re-apply DesignTokens migration, chrome tokens, settings
keys, view-mode bar onto upstream's ContentView/Settings/Panels/Sidebar. Build.

**Phase 5 — drop the superseded.** Evaluate `EditorTextView+RuntimePolicy` gating vs upstream
virtual editor + file-backed doc. Prefer upstream; keep only fork gating that adds unique value.

**Phase 6 — verify + land.** Matrix build (macOS + iOS sim + iPad sim), run tests, deploy to
`/Applications/nve.app`, sanity-test the tree-sitter toggle + large-file behavior. Then fast-forward
`fork/integration` to this branch (or open it as a PR against your fork's `main`).

## Why not a plain merge
A merge forces git's rename detection to reconcile your edits at old paths against upstream's edited
files at new paths, *and* pits your large-file/highlighting solutions against upstream's new
architecture in the same hunks. Layered re-apply lets you decide per-subsystem which solution wins,
and keeps each step build-verifiable.

## Effort estimate
~1 focused day. Phases 1–2 are mechanical (hours). Phases 3–5 are the real work (reconciling against
upstream's virtual editor + HTML scanner). Phase 6 is verification.

## Risks
- visionOS/iOS not compiler-verifiable locally (no simulators installed) — macOS-only verification.
- Upstream's virtual editor may change assumptions the tree-sitter seam relied on (whole-document
  parse). May need viewport-scoped parsing to fit the virtualized renderer.
- pbxproj SPM re-wire is the fragile hand-edit; snapshot + plutil-validate as before.
