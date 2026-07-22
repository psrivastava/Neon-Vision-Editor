# Fork Port Tasks — NotepadMac → Neon Vision Editor

Ordered implementation plan for the 10 agreed ports (see `NotepadMac-Feature-Comparison.md`).
All new code lands under `Neon Vision Editor/Fork/` (auto-compiled via the file-system-synchronized
group — **zero `project.pbxproj` edits**). Upstream files are touched only via tiny, clearly-marked
`// MARK: - FORK` hooks so future `upstream/main` merges stay clean.

## Isolation rules (recap)

- New behavior → **new files** in `Fork/`, types prefixed `Fork…`.
- Modify upstream behavior → prefer Swift `extension`s in Fork files + `Notification.Name` observers.
- Must-touch upstream file → one-line hook wrapped in `// MARK: - FORK … // END FORK`.
- Platform guards mandatory: AppKit behind `#if os(macOS)`, UIKit behind iOS guards.
- Swift 6 strict concurrency: new cross-isolation types `Sendable`; UI on `@MainActor`.
- Settings keys: `@AppStorage("SettingsX")`, defaults registered in `NeonVisionEditorApp`.

## Scope (finalized 2026-07-22, from annotated screenshot — 12 features)

Canonical list = the image the user annotated, minus two items pushed to Tier-3/later.
Net = **11 features** (+ task 0 scaffold).

Excluded / deferred:
- **Symbol outline sidebar** — already in NVE (`SidebarViews.swift:37`, `TOCItem.heading`). Not needed.
- **Custom theme editor + VS Code theme import** — Tier-3, later. Importing NotepadMac's curated theme
  set (task 11) gives a good-enough themes list on its own; the in-app color editor can come later.

Kept IN: multi-cursor, rendered↔raw switcher, and NotepadMac's curated theme set.

## Order (low-risk/isolated → high-risk/AppKit-internal)

Ordered so each task builds on the prior; riskiest AppKit work last. Task 0 is the enabling scaffold.

| # | Task | Surface | Risk | Upstream hook |
|---|------|---------|------|---------------|
| 0 | Fork infrastructure scaffold (`ForkCommand`, notification names, menu) | new | low | 1 menu block |
| 1 | String transforms suite | pure + menu | low | menu only |
| 2 | Document formatting XML/HTML (extend JSON) | pure + menu | low | menu only |
| 3 | Copy as HTML / Rich Text | AppKit read | low | menu only |
| 4 | CLI line:column (`nve` + open handler) | script + handler | low | open handler |
| 5 | Command palette (Cmd+Shift+P, distinct from Cmd+P) | new SwiftUI | med | 1 key binding |
| 6 | Breadcrumb bar (+ Copy Path/Name, Reveal, Rename) | new SwiftUI | med | 1 view insert |
| 7 | Encoding + line-ending detection/conversion | model + status | med | status bar insert |
| 8 | Rendered ↔ Raw view switcher (+ rendered-view line numbers) | preview + editor | med | toolbar/mode insert |
| 9 | Import NotepadMac's curated theme set (note 9.2) | model + assets | low | theme registry insert |
| 10 | Multi-cursor editing (Cmd+Click, Cmd+D, add above/below) | AppKit NSTextView | **high** | editor subclass hook |

**Tier-3 / later (not in this pass):** custom theme editor + VS Code theme import.

Notes-to-features mapping: 9.1 → task 4 (CLI col), 9.2 → task 9 (theme set import),
9.3 → task 6 (breadcrumb context menu), 9.4 → task 3 (copy as HTML).
"Line numbers in rendered markdown" (image #4) is folded into task 8's rendered view.

## Per-task detail

### 1. Fork scaffold
- `Fork/ForkSupport.swift` — `enum ForkCommand`, Fork `Notification.Name`s, a `ForkMenuCommands`
  SwiftUI `Commands` block, and shared helpers (active `NSTextView` accessor on macOS).

### 2. String transforms
- `Fork/ForkStringTransforms.swift` — pure `enum` of transforms (upper/lower/title/camel/snake/kebab,
  URL/Base64/HTML encode-decode, sort lines, dedupe, reverse, trim, hex↔dec). `Sendable`, testable.
- `Fork/ForkStringTransformsCommands.swift` — menu wiring → applies to active editor selection.
- Test: `Neon Vision EditorTests/ForkStringTransformsTests.swift`.

### 3. Document formatting XML/HTML
- `Fork/ForkDocumentFormatter.swift` — hand-rolled XML/HTML pretty/minify (Foundation only, no dep),
  delegating JSON to NVE's existing path. Test-covered.

### 4. Copy as HTML / Rich Text
- `Fork/ForkRichCopy.swift` (macOS) — reads the highlighted `NSTextView` attributed string →
  writes HTML + RTF flavors to the pasteboard.

### 5. CLI line:column
- Extend `scripts/nve`: accept `--column N` and `file:line:col` shorthand.
- `Fork/ForkOpenLocation.swift` — parse + route to existing `moveCursorToLine` / `moveCursorToRange`.

### 6. Command palette
- `Fork/ForkCommandPalette.swift` + `ForkCommandRegistry.swift` — new panel bound to `Cmd+Shift+P`,
  lists **actions only**. `Cmd+P` stays the document switcher (unchanged).

### 7. Breadcrumb bar
- `Fork/ForkBreadcrumbBar.swift` — path segments + language badge; context menu Copy Path / Copy Name /
  Reveal in Finder / Rename. Inserted above the editor.

### 8. Encoding + line endings
- `Fork/ForkEncoding.swift` (detect/convert, BOM + heuristic) + `Fork/ForkLineEndings.swift` (LF/CRLF/CR).
- Status-bar controls via a small Fork view inserted into the existing status row.

### 9. Theming parity
- `Fork/ForkThemeModel.swift` (Codable theme + JSON export/import),
  `Fork/ForkThemeEditorView.swift`, `Fork/ForkVSCodeThemeImporter.swift`.
- Layers onto `ThemeSettings.swift`; new settings sub-tab.

### 10. Rendered ↔ Raw switcher
- `Fork/ForkViewModeSwitcher.swift` — mode enum (Rendered / Raw) generalized beyond Markdown;
  rendered line-number gutter in the WebView HTML (`data-line` + CSS `::before`).

### 11. Multi-cursor
- `Fork/ForkMultiCursor.swift` (macOS) — additional cursors via Cmd+Click, Cmd+D select-next,
  add-cursor above/below; multi-range insert/delete. Highest risk; done last, behind a setting.

## Verification + deploy per build (STANDING WORKFLOW)
1. Add/adjust unit tests for pure-logic tasks; run `xcodebuild … test CODE_SIGNING_ALLOWED=NO`.
2. Build macOS (signing off): `xcodebuild … build CODE_SIGNING_ALLOWED=NO`.
3. **Every successful build → `scripts/fork/build-and-deploy.sh`**: Release archive → `shasum -a 256`
   hash-verified copy to `/Applications` (fails loudly on mismatch). The user tests only from
   `/Applications`, so this runs on every build — not just at the end.
4. **Commit + push to `origin` (fork) only on explicit user go-ahead** — never automatic.
   (`scripts/fork/push-fork.sh`, TBD.)
5. Before finishing shared/UI changes, also run `scripts/ci/build_platform_matrix.sh` when the iOS
   SDK is available (currently unavailable on this machine — iOS 26.4 not installed).
6. Remove any `.DerivedData*` folders created during manual verification.

## Status
- [x] 0 scaffold · [x] 1 transforms · [x] 2 formatter · [x] 3 rich copy · [x] 4 CLI loc  ← **Batch A, build-verified + tested (macOS, signing off)**
- [x] 5 command palette · [x] 6 breadcrumb · [x] 7 line-ending conversion  ← **Batch B, build-verified + tested (macOS, signing off)**
- [ ] 8 rendered↔raw · [ ] 9 theme set import · [ ] 10 multi-cursor  ← Batch C (remaining)
- Excluded: symbol outline sidebar (already in NVE)
- Tier-3/later: custom theme editor + VS Code theme import

### Batch B — done (2026-07-22)
Files added under `Fork/`: `LineEndings.swift` (detect + LF/CRLF/CR convert), `CommandRegistry.swift`
(action catalog + fuzzy filter), `CommandPalette.swift` (macOS NSPanel, Cmd+Shift+P, arrow/enter/esc
nav, routes to existing notifications). Test: `ForkLineEndingsTests.swift`.
Fork notifications added to `Support.swift`: `forkConvertLineEndingsRequested`,
`forkShowCommandPaletteRequested`. Handlers + `forkBreadcrumbBar` computed property added to
`ContentView+Commands.swift`; `BreadcrumbBar.swift` (path segments + language badge + Copy Path/Name
+ Reveal in Finder context menu), gated by `SettingsForkShowBreadcrumbBar` (default on).
Upstream hooks (all `// MARK: - FORK`): `MenuCommands.swift` (palette item Cmd+Shift+P + Convert Line
Endings submenu), `NeonVisionEditorApp.swift` (register default + install palette observer, both macOS
scene branches), `ContentView.swift` (breadcrumb insert above editor).
Note: Cmd+P (Quick Open) is untouched — palette is a distinct Cmd+Shift+P surface, per the scope note.
iOS matrix leg still unverifiable here (iOS 26.4 SDK/sim not installed).

### Batch A — done (2026-07-22)
Files added under `Neon Vision Editor/Fork/` (folder signals origin, so filenames drop the `Fork`
prefix; **type names keep it** — `ForkStringTransform`, `ForkDocumentFormatter` — since Swift has one
flat module namespace and the prefix is what prevents a future upstream type-name collision):
`Support.swift`, `StringTransforms.swift`, `DocumentFormatter.swift`, `MenuCommands.swift`,
`ContentView+Commands.swift`, `OpenLocation.swift`.
Tests: `ForkStringTransformsTests.swift`, `ForkDocumentFormatterTests.swift`.
Upstream hooks (3, all `// MARK: - FORK`): `ContentView.swift` (observer attach), `AppMenus.swift`
(menu, grouped w/ help to stay under builder child limit), `NeonVisionEditorApp.swift` (goto-URL).
CLI: `scripts/nve` gained `--column` + `file:line:col` shorthand → `neonvisioneditor://goto` URL.
Build: `xcodebuild … CODE_SIGNING_ALLOWED=NO` → **BUILD SUCCEEDED**, 0 compile errors.
Note: builds MUST pass signing-off flags here; plain build fails on provisioning (not a code issue).
Not yet run: unit tests (`xcodebuild test`) and platform matrix — pending.
