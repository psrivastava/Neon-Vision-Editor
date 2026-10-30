# Fork Port Manifest — replaying the fork onto a fresh upstream base

_Last updated: 2026-10-26. Base at time of writing: upstream `v2.1.3` (branch `rebuild/upstream-v2.1`)._

This file is the **authoritative record of everything the fork adds on top of upstream**, so the
whole set can be re-applied after upstream diverges (a hard rebase, re-clone, or big merge). It is
split into (1) purely additive files — carried by git, re-copyable by script; (2) SPM dependencies —
re-applied by script; (3) surgical edits to upstream files — marked in-source and listed here with
exact anchors so they can be replayed by hand or by the script.

## Toolchain prerequisite

Upstream `main` tracks the latest Xcode/OS SDK. As of this writing it requires **Xcode 27 (OS 27
SDK)** — the Foundation Models / Agent-Mode macros (`@Generable`, `@Observable`) fail to expand on
older Xcode with `swift-plugin-server produced malformed response`. The last upstream tag that builds
on Xcode 26.4 is **`v1.7.1`** (the macOS-27 editor-agent landed in `v1.7.2`). Pick the base
accordingly before porting.

Build/verify command (macOS, no signing):
```
xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" \
  -destination 'platform=macOS' -derivedDataPath /tmp/nve_dd \
  MACOSX_DEPLOYMENT_TARGET=15.5 CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

## 1. Additive files — the `Fork/` folder (no upstream edits)

All live under `Project/Sources/Neon Vision Editor/Fork/` and auto-include via the target's
`PBXFileSystemSynchronizedRootGroup` (no pbxproj entry needed). Tests under
`Project/Tests/Neon Vision EditorTests/`.

| File | Purpose | Coupling | Status |
|------|---------|----------|--------|
| `StringTransforms.swift` | case/slug transforms | Foundation only | ✅ ported + tested |
| `LineEndings.swift` | CRLF/LF conversion | Foundation only | ✅ ported + tested |
| `DocumentFormatter.swift` | XML/HTML prettify | Foundation only | ✅ ported + tested |
| `OpenLocation.swift` | open-at-location helper | AppKit | ✅ ported |
| `BreadcrumbBar.swift` | path breadcrumb view | pure SwiftUI | ✅ ported |
| `DesignTokens.swift` | `ForkDesign` tokens + ContentView helpers | needs `currentEditorTheme`, `EditorTheme` | ✅ ported |
| `ChromeStyle.swift` | themed-chrome colors on ContentView | needs `enableTranslucentWindow`, theme model | ✅ ported |
| `SyntaxEngine.swift` | engine toggle enum + `forkCurrentSyntaxEngine()` | Foundation only | ✅ ported |
| `TreeSitterHighlighter.swift` | tree-sitter engine, `#if canImport`-guarded | SwiftTreeSitter + grammars + `SyntaxColors`, `NVELock` | ✅ ported |
| Tests: `ForkStringTransformsTests`, `ForkLineEndingsTests`, `ForkDocumentFormatterTests` | | XCTest | ✅ ported + passing |

Tests tree-sitter relies on in upstream: `SyntaxColors` (Core/SyntaxHighlighting.swift) must expose
`tag, attribute, string, comment, number, atom, keyword, type, def, variable`; `NVELock`
(Core/NVELock.swift) must exist.

### Command subsystem — ✅ ported (⌘⇧P palette + Transform menu + string manipulations)
`CommandRegistry.swift`, `Support.swift`, `CommandPalette.swift` (macOS `#if`), `MenuCommands.swift`
(macOS `#if` — guarded because it uses `NSApp` and the `Fork/` group compiles into the iOS target
too), `ContentView+Commands.swift` (handlers). Wiring = edits E7–E9.
- **v2.1 adaptations** (macOS editor dropped `NSTextView`): transforms / markup / line-endings run on
  `currentContentBinding` (whole-document, mirroring upstream `transformCurrentJSONDocument`), guarded
  by `requiresMaterializedEditorTransform()`.
- **Degradations:** string transforms are whole-document (not selection-scoped); "Copy as Rich Text"
  copies **plain text** (no `NSTextStorage` to export HTML/RTF). Enhance if the virtual editor later
  exposes selection + an attributed snapshot.

### `MarkdownPreviewVivid.swift` — ✅ ported
Upstream's preview theming is a semantic-palette system with ~20 *fixed* templates; none is the
fork's live-editor-theme-tinted "Vivid". Port = the file + edits E5/E6. Base layout falls through to
the main `switch template` `default:` case; only prose chrome is tinted.

### Code folding (new feature, not a port) — tree-sitter-gated; ⌥1–9 fold / ⇧⌥1–9 unfold
- **Phase 1 ✅ (model):** `CodeFolding.swift` (`ForkFoldRange` + `ForkCodeFolding.normalize`/`levelRange`)
  and `forkTreeSitterFoldRanges(language:text:)` appended to `TreeSitterHighlighter.swift` (reuses the
  private per-language engine; derives line numbers from UTF-16 ranges, no Point API). Tested:
  `ForkCodeFoldingTests.swift`. Self-contained, no view code.
- **Phase 2 (pending):** editor integration in `VirtualEditorView+macOS.swift` — the hard part. That
  file is a windowed renderer: logical-line→visual-row is pure arithmetic
  (`logicalLineCount × estimatedRowsPerLogicalLine`) and only a viewport slice is read by physical
  line. Hiding ranges requires a logical→visible line remap threaded through the row index, viewport
  reads, caret math, scrolling, gutter chevrons + hit-testing, and line numbers. No existing fold hook.
  High risk to the perf-critical core; must be built as its own build-verified slice.

### Still deferred
- `PreviewOrientation.swift` — held by user; needs ContentView body wiring over v2.1's
  `ContentView+PreviewSplit` (its `markdownPreviewSplitTransition` member is absent).

## 2. SPM dependencies — tree-sitter grammars

Applied by `scripts/fork/apply-treesitter-spm.py` (idempotent; refuses if sentinel UUID `A1B2C3D4`
already present). Mirrors how Sparkle is linked, scoped to the **Neon Vision Editor Direct** target's
Frameworks phase. The `#if canImport(SwiftTreeSitter) && canImport(TreeSitterHTML)` guard in
`TreeSitterHighlighter.swift` keeps it inert in the App Clip / Share Extension targets (which share
the synchronized source group) without needing membership exceptions.

| Package | Version pin | Why |
|---------|-------------|-----|
| ChimeHQ/SwiftTreeSitter | upToNextMinor 0.9.0 | runtime |
| tree-sitter-html | upToNextMinor 0.23.2 | also used for XML (approx) |
| tree-sitter-css | **exact 0.23.2** | scanner.c manifest bug in 0.24+ (relative `fileExists` drops scanner.c → link error) |
| tree-sitter-json | upToNextMinor 0.24.8 | |
| tree-sitter-javascript | **exact 0.23.1** | scanner.c manifest bug; also used for TS (approx) |
| tree-sitter-python | **exact 0.23.6** | scanner.c manifest bug |
| tree-sitter-c | upToNextMinor 0.24.2 | also used for C++ (approx) |
| tree-sitter-bash | upToNextMinor 0.25.1 | |
| tree-sitter-go | upToNextMinor 0.25.0 | |
| tree-sitter-ruby | upToNextMinor 0.23.1 | |
| tree-sitter-rust | upToNextMinor 0.24.2 | |
| tree-sitter-java | upToNextMinor 0.23.5 | |

If a new/other grammar fails to link with `Undefined symbol: _tree_sitter_<lang>_external_scanner_*`,
pin it down to the last tag whose `Package.swift` lists `scanner.c` unconditionally.

## 3. Surgical edits to upstream files (replay by hand or script)

Each is marked in-source with a `FORK` or `FORK-SEAM` comment so it is greppable:
`grep -rn "FORK-SEAM\|// FORK" "Project/Sources"`.

| # | File | Anchor | Edit |
|---|------|--------|------|
| E1 | `UI/EditorTextView.swift` | in `fastSyntaxColorRanges`, right after `let lower = language.lowercased()` | `FORK-SEAM(tree-sitter)` block: if engine == .treeSitter and a grammar matches, `return forkTreeSitterColorRanges(...)`. Falls through (nil) otherwise. |
| E2 | `App/NeonVisionEditorApp.swift` | in `defaults.register(defaults: [ … ])` | register `"SettingsSyntaxEngine": SettingsSyntaxEngine.regex.rawValue` |
| E3 | `UI/NeonSettingsView.swift` | `@AppStorage` block near `generatedFileSyntaxHighlightingRaw` | add `@AppStorage("SettingsSyntaxEngine") … syntaxEngineRaw` |
| E4 | `UI/NeonSettingsView.swift` | in macOS `GroupBox("Editor Behavior")`, after the Performance "Balanced keeps default behavior" help text | the engine `Picker` + help text |
| E5 | `UI/ContentView+MarkdownPreviewExport.swift` | `markdownPreviewTemplateOptions`, after the `id: "default"` entry | add `MarkdownPreviewTemplateOption(id: "vivid", title: "Vivid")` |
| E6 | `UI/ContentView+MarkdownPreviewExport.swift` | in `markdownPreviewCSS`'s `templateAccentCSS` switch (first case) | `case "vivid": templateAccentCSS = forkVividAccentCSS(preferDarkMode: preferDarkMode)` |
| E7 | `UI/ContentView.swift` | body `onReceive` chain, before the `.markdownPreviewViewportDidChange` observer | 5 `// MARK: - FORK command observers` `.onReceive` modifiers (transform / format / minify / line-endings / copy), each gated by `forkMatchesWindow` |
| E8 | `App/NeonVisionEditorApp.swift` | macOS `.commands {` block, before `NeonVisionMacAppCommands(` | `ForkMenuCommands()` |
| E9 | `App/NeonVisionEditorApp.swift` | after each `.onAppear { scheduleMacWindowChromePolicy() }` | `.onAppear { #if os(macOS) ForkCommandPaletteInstaller.installIfNeeded() #endif }` |
| E10 | `UI/VirtualEditorView+macOS.swift` | `scheduleSyntaxHighlighting()` — capture `forkUseTreeSitter` near the other hoisted lets; add the whole-viewport tree-sitter branch before the per-line regex `for line in lines` loop | **The real macOS seam.** The virtual editor highlights per-line with regex and only routed JSON through `fastSyntaxColorRanges` (where E1 lives), so tree-sitter never reached Java/etc. This branch parses the whole viewport once via `forkTreeSitterColorRanges` and distributes spans across lines (mirrors the HTML path); nil → falls through to regex. E1 remains for iOS + JSON. |
| E11 | `UI/ContentView.swift` + `Fork/ContentView+Commands.swift` | `@AppStorage("SettingsSyntaxEngine") … forkSyntaxEngineRaw` by `highlightRefreshToken`; engine observation added to `ForkCommandObservers` (`syntaxEngineRaw` + `onSyntaxEngineChange` params, `.onChange` in the modifier body — NOT ContentView.body, to avoid the type-check timeout); call site passes `forkSyntaxEngineRaw` + `{ highlightRefreshToken &+= 1 }` | engine toggle bumps `highlightRefreshToken` (fed as `themeRefreshToken`) → `themeOnlyChanged` path clears `syntaxSpansByLine` + re-highlights instantly |
| E12 | `UI/VirtualEditorView+macOS.swift` | `drawWhitespaceAndIndentationDecorations` — the `showsIndentationGuides` branch | FORK cosmetic: replace the solid 1pt filled rect drawn at *every* leading space with a subtle dotted hairline at each indent *level* (`column % indentWidth == 0`), alpha 0.18. The upstream default looks like solid `|` pipes. |
| E13 | `UI/ContentView+MarkdownPreviewExport.swift` | `:root` CSS var `--md-heading-color` | FORK: set to `palette.accent` (was `palette.heading`, a near-text shade → headings were indistinguishable from body text). Colors `h1…h6` with the theme accent on every preview template. Keep the comment as a CSS `/* */` — the surrounding `"""` is an interpolated CSS string, so `//` would corrupt it. |
| E14 | `UI/VirtualEditorView+macOS.swift` | `draw`, the `if !translucentBackgroundEnabled` background-fill block | FORK: after the base fill, tint the gutter strip (0…`gutterWidth`) toward white/black (dark 5%, light 8% — light raised from 3.5%, which was invisible on cream themes) and draw a 0.5pt separator at `gutterWidth`, so the text area reads as a distinct surface. Only in the opaque path (translucent mode shows the material). |
| E15 | `UI/ContentView.swift` + `UI/NeonSettingsView.swift` + `UI/ContentView+TabChromeStatus.swift` | `@AppStorage("SettingsStatusBarShowLastModified")` in both views; `Toggle("Last Modified Time")` after the Git toggle (Settings); `lastModifiedStatusText` + append in `statusBarItems()` | FORK: status-bar "Modified: <date time>" from the tab's in-memory `lastKnownFileModificationDate` (no per-render filesystem stat). Default on. |
| E16 | `Fork/SurfaceStyle.swift` (new) + `UI/ContentView.swift` + `UI/ContentView+TabChromeStatus.swift` | ContentView: `@AppStorage(ForkSurfacePreset.storageKey)` beside `macTranslucencyModeRaw` (macOS block); `forkChromeColor(_:)` helper above `macSolidSurfaceColor`; early-return fork seams in `macSolidSurfaceColor`, `macEditorSurfaceBackgroundStyle`, `macChromeBackgroundStyle` (`.panel`) and `macToolbarBackgroundStyle` (`.tabStrip`). TabChromeStatus: status bar `.background` routed through `forkStatusBarBackgroundStyle` (`.statusBar`) | **A2 surface system.** Elevation-stepped chrome derived from the active editor theme's background hue (panels/window < status bar < tab strip < editor = theme bg, lightest), plus neutral White/Grey presets. Preset `upstream` (default) returns nil → all seams fall through to upstream behavior. Explicit Translucent Window wins over the fork preset; the preset *does* override the `!opaqueEditorCanvas` material path. Logic lives in `Fork/SurfaceStyle.swift`; each upstream edit is a 1-line seam. |
| E17 | `UI/NeonSettingsView.swift` | `@AppStorage(ForkSurfacePreset.storageKey)` beside `opaqueEditorSurfaceMac`; `forkChromeSurfacePicker` computed property in the `#if os(macOS)` helper block; one `forkChromeSurfacePicker` line after the Opaque Editor Canvas toggle | FORK: Settings → "Chrome Surface" menu picker (Default / Theme Tint / White / Grey), disabled while Translucent Window is on. Kept as a computed property to avoid inflating the settings body expression (type-check limit). **Default is `theme` (Theme Tint)** in both `@AppStorage` declarations (E16 + E17) — with the `upstream` default the feature was invisible out of the box. |
| E18 | `UI/ContentView.swift` | `editorView` — `effectiveHighlightCurrentLine` no longer ANDs `!shouldThrottleFeatures` | FORK: current-line highlight stays on for large files (it only fills one rect over already-laid-out viewport rows, same cost class as selection drawing). The ≥450k-UTF16 heavy-feature throttle still disables scope guides, bracket matching, scope background, and completion. Without this, current-line looked like a per-language bug (big JSON throttled, small XML/Java not). |
| E19 | `Fork/CodeReindenter.swift` + `Fork/FormatRouter.swift` + `Fork/PaletteBridge.swift` (all new) + `Fork/ContentView+Commands.swift` + `Fork/Support.swift` + `Fork/CommandRegistry.swift` + `Fork/MenuCommands.swift` + `UI/ContentView+Actions.swift` + `UI/ContentView+QuickSwitcherFind.swift` + `UI/ContentView.swift` + `UI/ContentView+TabChromeStatus.swift` | **Upstream seams are 4 lines total.** Actions: `formatJSONDocument()` / `combineJSONLines()` keep upstream's JSON-language guard, then call `forkFormatDocument(pretty:)`. QuickSwitcherFind: `items.append(contentsOf: ForkPaletteBridge.items)` after the upstream `commandItems` append, and `forkRunPaletteCommand(commandID)` in the `default:` arm of `performQuickSwitcherCommand` (passes `hostWindowNumber` — `NSApp.keyWindow` is the palette sheet at selection time, which `forkMatchesWindow` would reject). ContentView: new `@State var forkStatusMessage`. TabChromeStatus: `statusBarItems()` prepends it when non-empty. | **Unified document formatter.** `ForkFormatRouter` routes by language: JSON → upstream `JSONPreviewDocument.formattedText`, XML/HTML/SVG → `ForkDocumentFormatter`, C-family → new `ForkCodeReindenter` (bracket-depth re-indent; block comments and multi-line strings emitted verbatim). `forkFormatDocument(pretty:)` replaces the markup-only handler and **works on file-backed documents** by materializing via `tab.document.string()` + `tab.replaceContentStorage(with:markDirty:)` under a 10 M-UTF16 ceiling, with a partial-preview guard — upstream's `requiresMaterializedEditorTransform()` guard made Format JSON a silent no-op on exactly the large files that need it. New notifications `forkFormatDocumentRequested` / `forkMinifyDocumentRequested` + two observers on the existing `formatMarkup` closure. `ForkPaletteBridge` projects the whole fork registry into **upstream's** palette (the one titled "Command Palette"), so there is one searchable list instead of two divergent ones. **Bug fixed after first build:** every fork command (format, minify, string transforms, line endings, copy-rich-text — old and new) reported through upstream's `findStatusMessage`, which only renders inside the inline Find bar (`ContentView.inlineFindBar`, gated by `showFindReplace`). With Find closed, every fork action — success, failure, or no-op — looked identical: silent. Added a dedicated `forkStatusMessage` surfaced in the always-visible status bar instead. |
| E20 | `Fork/MenuCommands.swift` | fork palette `.keyboardShortcut` moved from ⌘⇧P to ⌘⇧K; button retitled "Fork Command Palette…"; new "Format Document (Prettify)" item at ⌘⌥⇧F | FORK: upstream already binds ⌘⇧P to "Toggle Document Preview" (`App/AppMenus.swift`), so the fork palette's duplicate binding meant it never opened — the palette users actually saw was upstream's. Verified ⌘⇧K and ⌘⌥⇧F are unused across the project and `Core/ShortcutPreferences.swift`. |

### Not yet applied (optional polish)
- **Live re-highlight on toggle:** ✅ done (E11) — `.onChange(of: forkSyntaxEngineRaw)` bumps
  `highlightRefreshToken`.
- **HTML/CSS tree-sitter upgrade on macOS:** the E10 branch is scoped to the regex-path languages;
  HTML keeps its dedicated `HTMLSyntaxHighlighter` (the `initialHTMLState` path), so tree-sitter does
  not yet upgrade HTML/CSS/XML in the macOS virtual editor. Extend E10 to cover the HTML path if desired.
- iOS/visionOS Settings: E4 adds the picker to the macOS `GroupBox` only; the iOS
  `editorBehaviorSettings` branch needs the same picker for parity.

## 4. Replay procedure (after a big upstream divergence)

1. Branch off the chosen upstream base (`git switch -c rebuild/upstream-<ver> upstream/main`), after
   confirming the toolchain prerequisite above.
2. Restore the `Fork/` folder + 3 tests (git carries them across rebase; if re-cloning, copy from the
   last fork branch: `git show <fork-branch>:<path>`).
3. Run `python3 scripts/fork/apply-treesitter-spm.py` from the repo root; `plutil -lint` the pbxproj.
4. Re-apply edits E1–E4 (grep the FORK markers in the old fork tree for the exact blocks).
5. Build with the command above. Fix any grammar scanner.c link errors by pinning (section 2).
6. Port the deferred command-palette subsystem as a separate build-verified slice if desired.
