# Fork Developer Notes — enhancements & learnings

_Companion to `Fork-Port-Manifest.md` (the exact replay record). This file is the narrative: what the
fork adds on top of upstream `v2.1.x`, and the engineering learnings/gotchas worth keeping so the next
person (or the next rebase) doesn't rediscover them the hard way._

Branch: `rebuild/upstream-v2.1`. Deploy target: `/Applications/nve.app` (via
`scripts/fork/build-and-deploy.sh`). The fork is only ever tested from `/Applications/nve.app`.

## Enhancements delivered

| Feature | What it does | Where |
|---|---|---|
| **Tree-sitter syntax engine** | Settings → Editor toggle. Tree-sitter gives structural coloring (keywords/types/strings/etc.) for 11 grammars; Regex is the classic per-language highlighter. Falls back to regex for languages without a grammar. | `Fork/SyntaxEngine.swift`, `Fork/TreeSitterHighlighter.swift`, seam in `VirtualEditorView+macOS.swift` |
| **Live engine toggle** | Flipping the engine re-highlights the open document instantly (no edit/reopen needed). | `Fork/ContentView+Commands.swift` (`ForkCommandObservers`) → bumps `highlightRefreshToken` |
| **Vivid markdown preview** | A preview template tinted by the live editor theme (distinct from upstream's fixed templates). | `Fork/MarkdownPreviewVivid.swift` |
| **Command palette + Transform menu** | ⌘⇧P fuzzy command palette; a Transform menu with case/encoding/line ops, XML/HTML format+minify, line-ending conversion, copy. | `Fork/CommandRegistry.swift`, `Fork/CommandPalette.swift`, `Fork/MenuCommands.swift`, `Fork/ContentView+Commands.swift` |
| **Text utilities** | String transforms, line-ending conversion, XML/HTML document formatting (pure, unit-tested). | `Fork/StringTransforms.swift`, `Fork/LineEndings.swift`, `Fork/DocumentFormatter.swift` |
| **Subtle indentation guides** | Replaced upstream's solid per-space pipe with a faint dotted hairline per indent level. | `VirtualEditorView+macOS.swift` `drawWhitespaceAndIndentationDecorations` |
| **Code folding — model only** | `ForkFoldRange` + tree-sitter fold-range computation. Editor integration (hiding lines) is **not** built. | `Fork/CodeFolding.swift`, `forkTreeSitterFoldRanges` in `Fork/TreeSitterHighlighter.swift` |
| **Window shell redesign (NotepadMac-style)** | Three rounded 12pt cards (TOC / editor / project) on a themed backdrop; gutters double as resize handles; traffic lights sit over the left card; in-app pill tabs replace the native window tab bar. | `UI/ContentView.swift` (`macOSTOCSplitLayout`, `macShellBackdropColor`), `UI/SidebarViews.swift`, `UI/ContentView+ProjectSidebar.swift`, `Fork/SurfaceStyle.swift` (`shellBackdrop`, `panelCardFill`) |
| **In-editor title row + overflow toolbar** | Window `NSToolbar` is hidden; the title row (sidebar toggle, app icon + name, 6 inline actions in a rounded group, `⋯` overflow menu, right sidebar toggle) lives in the editor card header. Uses `ViewThatFits` so the row degrades 6→3→0 inline actions as the window narrows, then relies on the overflow menu — nothing ever clips. | `UI/ContentView+Toolbar.swift` (`forkTitleBar`, `forkTitleBarActions`, `macDocumentToolbarGroups`) |
| **In-app document tab pills** | Native window-tabbing disabled via `MacDocumentTabPolicy.forkInAppTabsEnabled`; file-opens stay in the current window as pills. Hover shows the `~`-abbreviated path; right-click gives Close Tab / Close Other / Close to the Right / Copy File Name / Copy File Path / Reveal in Finder. Two-tone treatment: current tab filled, previously-selected tab muted accent. | `UI/ContentView+TabChromeStatus.swift` (`forkMacTabStrip`, `forkMacTabPill`, `forkMacTabContextMenu`), `App/MacDocumentWindowTabs.swift` (`preferredTabbingMode`, destination nulled when in-app tabs on), `UI/ContentView.swift` (`previousSelectedTabID`) |
| **Right sidebar — Git + Terminal tabs, sync-to-current-file** | Added a `Git` tab (unconditional; renders `gitFileStatusMap` as A/M/D/R rows, click opens file). Terminal tab is already present under `#if os(macOS) && !APP_STORE_BUILD`. Sync-to-current-file button (⇄, `arrow.left.arrow.right`) expands the tree to the selected tab's file. Tab pills have the same two-tone treatment as document pills. | `UI/SidebarViews.swift` (`ProjectSidebarTab.git`, `gitContent`, `gitChangeRow`, `tabButton` previous-tint, sync button in `filesContent`) |
| **Native-drag resize handles** | Resize divider's hover area used to be a transparent SwiftUI view, which lost the mouse to AppKit neighbours (editor) and let `isMovableByWindowBackground` turn the gesture into a window move. Added an `onNativeDrag` path on `MacSidebarResizeDivider` — the AppKit tracking view handles mouseDown/Dragged/Up in window coordinates, overrides `mouseDownCanMoveWindow = false`, and biases its hit area away from the editor. | `UI/ContentView+ProjectSidebar.swift` (`MacSidebarResizeDivider.onNativeDrag`, `MacSidebarResizeCursorTrackingView.TrackingView`) |
| **Deploy guard: don't swap bundle under a running instance** | `scripts/fork/build-and-deploy.sh` now asks `/Applications/nve.app` to quit via `osascript "quit app"` before the clean-copy step (unix inodes stay mapped under a running process — rm+cp "works" on disk but the live process keeps running the old binary from memory). Waits up to 15 s; aborts if the app is still up (e.g. an unsaved-changes prompt). | `scripts/fork/build-and-deploy.sh` |

## Learnings & gotchas (the expensive ones)

1. **The macOS editor is a *virtual* renderer, not `NSTextView`.** `VirtualEditorView+macOS.swift` is a
   windowed, custom-drawn surface. Two big consequences:
   - **Syntax seam lives in the wrong place by default.** Coloring is computed per-line in
     `scheduleSyntaxHighlighting()`, and upstream only routes **JSON** through `fastSyntaxColorRanges`
     (where the fork's original `fastSyntaxColorRanges` hook sat). So a hook there is invisible to every
     other language on macOS. The fix: a whole-viewport tree-sitter branch *inside*
     `scheduleSyntaxHighlighting()` that parses once and distributes color ranges across lines — the
     same shape as the existing HTML highlighter path. **Lesson: verify which code path actually paints
     the macOS editor before wiring a seam; `EditorTextView` is iOS + JSON-only on macOS.**
   - **Command transforms can't use `NSTextView`/`NSTextStorage`.** They operate on
     `currentContentBinding` (whole-document), and "Copy as Rich Text" degrades to plain text.

2. **SwiftUI body type-check timeout is a hard ceiling.** `ContentView.body` is enormous; adding even
   one more `.onChange`/`.onReceive` tips it into *"unable to type-check this expression in reasonable
   time."* **Lesson: never add observers directly to `ContentView.body`.** Bundle them into a single
   `ViewModifier` (`ForkCommandObservers`) — the closures resolve inside the modifier, not the body.
   The engine-toggle observer had to move there too.

3. **Default actor isolation is `@MainActor`.** New `public` types silently become MainActor-isolated,
   which breaks calls from `nonisolated` code (the off-main highlighter). Mark value types that cross
   into nonisolated code `public nonisolated` (see `ForkFoldRange`, `ForkCodeFolding`).

4. **Agent can't build; the human builds.** The agent sandbox mangles `swift-plugin-server` stdio, so
   macro expansion (`@Generable`, `@Observable`) fails in-agent for *all* targets. All builds/deploys
   run in the user's Terminal; the agent iterates by reading the error lines. Build command and deploy
   script are in `Fork-Port-Manifest.md` / `scripts/fork/`.

5. **Xcode 27 / OS 27 SDK is required by upstream `main`.** The Foundation Models / Agent-Mode macros
   don't expand on Xcode 26.x. Last tag buildable on 26.4 is `v1.7.1`.

6. **tree-sitter grammar pins matter.** css/js/python are pinned to exact older tags because 0.24+
   `Package.swift` manifests drop `scanner.c` and fail to link (`Undefined symbol:
   _tree_sitter_<lang>_external_scanner_*`). See the pin table in `Fork-Port-Manifest.md`.

7. **A symbol/outline navigator already exists upstream** (`DocumentSymbolNavigator`, "Go to Symbol",
   outline sidebar) — so there's no need to build structure-navigation; it's regex-based and could be
   upgraded to tree-sitter later if desired.

8. **The editor card's header host swallows the titlebar's reserved space.** The macOS title row is
   rendered through `MacDocumentContentController` as an `NSHostingView` accessory. Hosting views are
   safe-area-aware by default on macOS Sequoia+: with the window's `fullSizeContentView` style the host
   silently pads itself down by the titlebar height, so the toolbar row sits below an empty band even
   though the SwiftUI view says it's flush. **Lesson: set `host.safeAreaRegions = []` on every
   `NSHostingView` in the editor stack** (header + replacement region), not just the per-pane header.
   See `MacDocumentContentController.swift` lines 108 (`updateAccessory`), 274 (per-pane header), 348
   (region host).

9. **SwiftUI `isMovableByWindowBackground` beats custom gestures.** With the window set movable by its
   background, a transparent SwiftUI view handling a `DragGesture` loses the first mouse-down to
   AppKit's window-drag path. Resize handles need either `mouseDownCanMoveWindow = false` on an actual
   `NSView`, or AppKit-side mouse tracking (`mouseDown`/`mouseDragged`/`mouseUp`). The fork uses the
   second — a `TrackingView` that measures translation in window coordinates and drives the width
   state directly. **Lesson: never trust SwiftUI gestures for resize-adjacent-to-AppKit chrome when
   the window is movable by background.**

10. **The release-copy script needs a liveness guard.** `rm -rf /Applications/nve.app && cp -R` under
    a running instance succeeds silently on disk, but the kernel keeps the old inodes mapped for the
    live process, so the user keeps testing yesterday's binary while trusting today's hash. Any lazy
    resource read from the live process can then mismatch the swapped bundle and crash. The script
    now asks the app to quit via `osascript "quit app"` before the copy and aborts if it stays up.

11. **Native `NSToolbar` always wins hit-testing at the window top.** Hiding it (`isVisible = false`)
    is enough to free the band for SwiftUI content, but the title text can still re-appear whenever
    `window.title` is set. Keep `window.titleVisibility = .hidden` reasserted inside
    `applyDocumentMetadata`, not just once at window creation.

## Known limitations / next candidates

- **Code folding (true in-editor)** — the model is built; hiding lines + gutter chevrons needs a
  logical→visible line remap through the virtual renderer's row-index, viewport reads, caret/scroll
  math, and gutter. High risk to the perf-critical core; deferred.
- **HTML/CSS tree-sitter** — the macOS tree-sitter branch is scoped to the regex-path languages; HTML
  keeps its dedicated highlighter, so tree-sitter doesn't yet upgrade HTML/CSS/XML on macOS.
- **Selection-scoped transforms** and **true rich-text (HTML/RTF) copy** — blocked on the virtual
  editor exposing a selection snapshot / attributed storage.
- **iOS/visionOS settings parity** — the engine picker is macOS-only.
- Preview orientation toggle — held.

## How to re-port after an upstream rebase

See `Fork-Port-Manifest.md` §4 (replay procedure) — it lists every additive file, the SPM splice
script, and the surgical edits E1–E12 with exact anchors.
