# NotepadMac → Neon Vision Editor — Feature Comparison

Purpose: identify features built in **NotepadMac** (`~/MyProjects/NotepadMac`) that are **not yet in
Neon Vision Editor (NVE)**, so we can decide which to port into this fork.

Both are native macOS SwiftUI + `NSTextView`/TextKit editors that communicate via `NotificationCenter`.
Their most important architectural difference shapes what is easy vs hard to port:

| | NotepadMac | Neon Vision Editor |
|---|---|---|
| Syntax highlighting | **Scintilla C++ lexers** via an Obj-C++ `LexerBridge` (100+ langs, fold levels) | **Regex-based** in-Swift (`Core/SyntaxHighlighting.swift`), throttled/bounded |
| Platforms | macOS only | macOS + iOS + iPadOS + visionOS |
| Build | SPM | Xcode project (App Store + notarized) |

That lexer difference matters: NotepadMac's **code folding, hex view, and custom-language regex rules**
lean on Scintilla fold levels / infrastructure NVE doesn't have, so those are the higher-effort ports.

Legend — **NVE status**: ✅ has it · ⚠️ partial/different · ❌ missing.

---

## Comparison table (features NotepadMac has)

### Editor core

| Feature | NotepadMac | NVE status | Notes on the gap |
|---|---|---|---|
| Multi-cursor editing (Cmd+Click, Cmd+D select-next, add cursor above/below) | ✅ `NMTextView+MultiCursor.swift` | ❌ | Not present. High user value, medium effort on `NSTextView`. |
| Vertical block / column selection | ✅ `NMTextView+BlockSelection.swift` | ❌ | Not present. |
| Code folding (fold all / by level, gutter triangles) | ✅ `NMTextView+Folding.swift` (Scintilla fold levels) | ❌ | Missing. Higher effort — NVE has no fold-level source; would need indentation/bracket-based folding. |
| Bracket auto-close + matching | ✅ | ⚠️ | NVE has bracket-scope **matching/highlighting**; auto-close on type not confirmed. |
| Auto-completion popup (keywords + doc words) | ✅ `LexerKeywords.swift` | ⚠️ | NVE has AI + local `CompletionHeuristics`; different UX (inline vs popup menu). |
| Copy as HTML / rich text | ✅ `attributedStringToHTML` | ❌ | Not present as a copy action. |
| 25 string transforms (case, encoding, escaping, sort/dedupe, hex↔dec) | ✅ `StringTransforms.swift` | ❌ | NVE has JSON pretty/minify only; no broad transform suite. |
| Document formatting (JSON/XML/HTML pretty + minify) | ✅ `DocumentFormatter.swift` | ⚠️ | NVE does **JSON** pretty/minify (`ContentView+Actions.swift:329`); no XML/HTML. |

### Markdown / rendered

| Feature | NotepadMac | NVE status | Notes |
|---|---|---|---|
| Rendered markdown preview | ✅ | ✅ | NVE `MarkdownPreviewWebView` + HTML/**PDF export** (NVE is ahead here). |
| Line numbers in rendered view | ✅ `data-line` CSS gutter | ❌ | Missing in NVE preview. |
| Find in rendered view (`window.find()`) | ✅ | ⚠️ | Verify — NVE preview find not confirmed. |
| Mermaid diagram rendering | ✅ offline Mermaid 11 | ✅ | NVE renders mermaid in export/preview HTML (`ContentView+MarkdownPreviewExport.swift:1179`). |
| Plain-text reading view (reflow, proportional font) | ✅ `PlainTextRenderedView.swift` | ❌ | Missing. |

### Navigation & files

| Feature | NotepadMac | NVE status | Notes |
|---|---|---|---|
| File tree sidebar | ✅ | ✅ | Both have it. |
| Symbol **outline sidebar** (filterable, click-to-nav) | ✅ `SymbolOutlineView.swift` | ⚠️ | NVE has **Go-to-Symbol** via quick switcher (`DocumentSymbolNavigator`), not a persistent outline panel. |
| Breadcrumb bar (path segments, language badge, rename/reveal) | ✅ `BreadcrumbBarView.swift` | ❌ | No breadcrumb bar in NVE. |
| Quick Open (Cmd+P fuzzy) | ✅ | ✅ | NVE `ContentView+QuickSwitcherFind`. |
| Recent files (MRU) | ✅ | ✅ | NVE `RecentFilesStore`. |
| Welcome overlay | ✅ | ✅ | Both have it. |
| Native tabs & multi-window | ✅ | ✅ | Both. |
| Command-line open (`+line:col`) | ✅ `np` | ✅ | NVE `nve` helper. |

### Search

| Feature | NotepadMac | NVE status | Notes |
|---|---|---|---|
| In-file find/replace (regex, word, case, highlight-all) | ✅ | ✅ | Both. |
| Find in Files (project-wide, cancellable) | ✅ | ✅ | NVE prefers `rg`. |
| Search results panel | ✅ bottom panel | ✅ | NVE sidebar Search tab. |

### UI / theming

| Feature | NotepadMac | NVE status | Notes |
|---|---|---|---|
| Design token system | ✅ `DesignConstants.swift` | ✅ | NVE has themes/tokens. |
| Built-in themes | ✅ 12 | ✅ | NVE has its own theme set (`ThemeSettings.swift`). |
| **Custom theme editor** (edit colors, JSON export) | ✅ `ThemeEditorView.swift` | ❌ | NVE has theme selection but no in-app color editor. |
| **VS Code theme import** | ✅ `VSCodeThemeImporter.swift` | ❌ | Missing. |
| Command palette (Cmd+Shift+P, 70+ commands) | ✅ `CommandPaletteView.swift` | ⚠️ | NVE has Quick Open (files/symbols); no general command palette. |
| Follow system appearance | ✅ | ✅ | Both. |

### Terminal / panels

| Feature | NotepadMac | NVE status | Notes |
|---|---|---|---|
| Integrated terminal (real `$SHELL`, history, cd, ANSI) | ✅ `TerminalPanel.swift` | ⚠️ | NVE has a **lightweight** terminal surface (`IntegratedTerminalContent`); NotepadMac's is richer (rc-file sourcing, launch in Terminal.app/iTerm, auto-cwd). |
| Bottom panel (Cmd+J tabbed) | ✅ | ⚠️ | NVE uses sidebar tabs rather than a bottom panel. |

### Distinctive / power-user

| Feature | NotepadMac | NVE status | Notes |
|---|---|---|---|
| Hex view (hex + ASCII) | ✅ `HexView.swift` | ❌ | Missing. |
| CSV / delimited table view | ✅ `CSVTableView.swift` | ✅ | NVE has delimited table mode (`ContentView+StructuredData.swift`). |
| Plist structured view | — | ✅ | NVE-only (`PlistViewMode`). |
| Crash-report view | — | ✅ | NVE-only (`AppleCrashReportParser`). |
| Word count in status bar | ✅ | ✅ | NVE `scheduleWordCountRefresh`. |
| Git branch indicator in status bar | ✅ | ✅ | NVE `ContentView+TabChromeStatus.swift:342`. |
| Encoding detection & conversion (13 encodings) | ✅ `EncodingDetector.swift` | ❌ | Missing. |
| Line-ending detect/convert (LF/CRLF/CR) | ✅ | ⚠️ | NVE references line endings; full convert UI not confirmed. |
| External file-change detection + conflict dialog + backups | ✅ | ✅ | NVE `ExternalFileConflictState` in `EditorViewModel`. |
| Custom user-defined languages (keywords + regex rules) | ✅ `CustomLanguage.swift` | ❌ | Missing. |
| Custom extension→language mappings | ✅ | ⚠️ | NVE has `LanguageDetector`; user-override UI not confirmed. |

### Features NVE has that NotepadMac lacks (context)

NVE is not strictly behind — it leads on: **cross-platform (iOS/iPadOS/visionOS)**, **PDF export**,
**AI completion** (Apple FoundationModels + OpenAI/Gemini/Anthropic/Grok), **Vim mode**, **code
minimap**, **focus-mode window**, **diff / folder compare**, **remote sessions**, **SVG preview**,
**code snapshot composer**, **plist / crash-report structured views**, **App Clip + Share Extension**,
**Sparkle + App Store delivery**, and **localization (en/de/zh)**.

---

## Agreed port scope (finalized 2026-07-21)

Effort assumes NVE's regex-highlighting model (no Scintilla). Tier 3 is **set aside** (see bottom).
Items below reflect the review notes: #5 (outline) dropped as already-present, and the 9.x additions
folded in as first-class scope.

### Tier 1 — high value, good fit, isolated (port first)

1. **Multi-cursor editing** — big editor upgrade; self-contained `NSTextView` extension.
2. **String transforms suite** (case/encoding/sort/dedupe/base64…) — pure functions + menu; trivially isolated as fork files.
3. **Command palette (Cmd+Shift+P)** — **must be a distinct surface from Quick Open.**
   - `Cmd+P` = document/file switcher **only** (NVE's existing `ContentView+QuickSwitcherFind`).
   - `Cmd+Shift+P` = commands **only** (new palette). Do not overload one panel with a mode toggle;
     build the command palette as its own fork surface that lists actions, not files.
4. **Rendered ↔ Raw view switcher** (supersedes "line numbers in rendered MD"):
   - Add a **Rendered vs Raw mode switch** like NotepadMac (NVE today only has a preview *split-pane
     toggle*, not a mode switch — confirmed in `ContentView+Toolbar.swift`).
   - The switch should generalize beyond Markdown — e.g. a formatted view vs plain-text view for other
     languages too.
   - Include **line numbers in the rendered view** (the original small WebView change) as part of this.

### Tier 2 — valuable, moderate effort

5. **Breadcrumb bar** — self-contained view; reads current file/language.
   Include **context-menu actions: Copy Path, Copy Name, Reveal in Finder, Rename** (per note 9.3).
6. **Encoding + line-ending detection/conversion** — model + status-bar UI.
7. **Document formatting for XML/HTML** — extends NVE's existing JSON formatter.
   - **Answer to the note:** NotepadMac's `DocumentFormatter.swift` is **hand-rolled**, not a library —
     JSON via Foundation `JSONSerialization`, XML/HTML via a manual walker. NVE would extend its own
     JSON pretty/minify path (`ContentView+Actions.swift:329`) the same way. **No new dependency.**
8. **CLI line:column invocation** (note 9.1) — NVE's `nve` helper supports `--line N` but **not column**
   and not the `file:line:col` shorthand NotepadMac's `np` uses. Add column support + the shorthand.
9. **Theming parity** (note 9.2) — NotepadMac has richer theming (12 curated themes, custom theme
   editor with color editing + JSON export, **VS Code theme import**). Bring these over onto NVE's
   theme model (`ThemeSettings.swift`). Combines the earlier "VS Code import / custom theme editor" item.
10. **Copy as HTML / Rich Text** (note 9.4) — `attributedStringToHTML`-style copy action from the
    highlighted editor buffer. Small, self-contained.

### Dropped from scope

- **Symbol outline sidebar** — NVE already has a sidebar TOC/headings + function navigator
  (`SidebarViews.swift:37`, `TOCItem.heading`). No work needed. *(was Tier-2 #5)*

### Set aside (Tier 3 — not now)

Recorded for completeness; **not planned**: code folding, hex view, column/block selection, custom
user-defined languages, richer integrated terminal.

**Fork-workflow note:** per our isolation strategy, these items are ideal ports — they land as
**new files** under a `Neon Vision Editor/Fork/` folder (auto-compiled via the file-system-synchronized
group, no `project.pbxproj` edits) and hook in through existing `Notification.Name` commands, keeping
upstream merges clean.

---

## Caveats / to-verify before committing

A few NVE statuses are marked ⚠️ pending a direct check: markdown-preview find, bracket auto-close,
line-ending conversion UI, and custom extension-mapping UI. Confirm these against source before we
scope any port that overlaps them.
