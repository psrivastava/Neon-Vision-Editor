# Neon Vision Editor — Syntax Engine Plan (regex ↔ tree-sitter, toggleable)

Goal: fix the thin HTML/CSS/XML/C token coloring by adding **tree-sitter** as a second
highlighting engine, selectable from a **Settings toggle**, so both engines can be A/B compared
per language on real files. Tree-sitter is **additive and reversible**: regex stays the default
and the universal fallback; tree-sitter only *upgrades* the languages that have a loaded grammar.

Status: **Phase A (toggle plumbing, regex-only)** first; then **Phase B (tree-sitter + HTML
end-to-end)**; then expand to CSS/XML/C.

---

## Why tree-sitter

The current engine is per-language `NSRegularExpression` tables + hand-written scanners. Regex
can't express **nesting** (CSS/JS inside HTML) or **error recovery** (malformed markup), so the
HTML fast scanner colors the whole `<…>` span one color — no tag/attr/value/comment distinction.
Tree-sitter is an incremental, error-tolerant parser (Zed, Neovim, GitHub, Nova by Panic), pure
C, MIT, notarization-clean.

**Binding:** SwiftTreeSitter + Neon (ChimeHQ, BSD-3) — layers onto the existing
`NSTextView`/`UITextView`, highlighting only, **no editor rewrite**. Rejected: Runestone
(iOS/Catalyst-only, full editor), STTextView (GPL/commercial — license blocker vs Apache-2.0),
Highlightr (unmaintained 2026).

---

## Architecture: one seam, one enum

### The toggle

```swift
enum SettingsSyntaxEngine: String, CaseIterable {
    case regex        // default — the existing NSRegularExpression tables + scanners
    case treeSitter   // upgraded parse where a grammar is loaded; regex fallback otherwise
}
```

`@AppStorage("SettingsSyntaxEngine")`, default `regex`, registered centrally in
`NeonVisionEditorApp`, exposed as a Settings picker in `NeonSettingsView`. Flipping it bumps
`highlightRefreshToken` (the same lever theme/translucency changes use) so the open document
re-highlights live — enabling instant A/B on the same file.

### The single seam

`fastSyntaxColorRanges(language:profile:text:in:colors:)` (in `EditorTextView.swift`) is the one
chokepoint every highlight pass already funnels through before falling back to the regex
`patterns(for:)` table. Tree-sitter plugs in **here**:

```
fastSyntaxColorRanges(...)                       // nonisolated, off-main-thread
├── engine == .treeSitter && grammarLoaded(lang)?
│     └── ForkTreeSitterHighlighter.colorRanges(language:text:range:colors:)  // → [(NSRange,Color)]
│         (nil → fall through to regex, so an unloaded grammar never breaks a language)
├── CSV → forkCSVRainbowColorRanges (unchanged)
├── HTML/XML .htmlFast → fastHTMLSyntaxColorRanges (regex, unchanged)
├── JSON → JSON scanner (unchanged)
└── else → nil → caller runs patterns(for:) regex table (unchanged)
```

Key property: the tree-sitter path returns the **same `[(NSRange, Color)]` shape** the pipeline
already consumes, with tokens mapped to the **active theme's `SyntaxColors`** — so it honors themes
(and the CSV-rainbow-style theming) automatically, and large-file gating / viewport limiting stay
exactly as they are.

---

## Tree-sitter integration details (Phase B)

### Packaging & linkage

Each grammar is its own C SPM package (`tree-sitter-html`, `-css`, `-xml`, `-c`). Added to the
Xcode project via **File → Add Package Dependencies** (this repo has no `Package.swift`; deps live
in the `.xcodeproj`). SwiftTreeSitter + Neon are Swift packages; the grammar packages ship the C
parser + `highlights.scm` query files as SPM resource bundles. All statically linked into the app
binary — no dylib, no entitlement, notarization treats it like any bundled native code.

### Token → color mapping

Tree-sitter highlight queries emit **capture names** (`@keyword`, `@string`, `@tag`,
`@attribute`, `@comment`, `@number`, `@type`, …). A small table maps each capture to a
`SyntaxColors` field — the same theme colors the regex engine uses — so tree-sitter output is
theme-consistent with the rest of the editor.

### UTF-16 ↔ byte-range bridging (the sharp edge)

Tree-sitter works in **UTF-8 byte offsets**; `NSTextStorage`/`NSRange` are **UTF-16**. The scanner
receives an `NSString` + a UTF-16 `NSRange`. Bridging: encode the (sub)string to UTF-8 for the
parser, translate node byte-ranges back to UTF-16 `NSRange` before returning. Validate every range
against `utf16Length` (the pipeline already has `isSyntaxHighlightRangeValid`). Get this wrong and
colors smear on any non-ASCII content (the drawio XML has Japanese labels — a good test).

### Concurrency (Swift 6 strict)

Tree-sitter `Parser`/`Tree` objects are **not thread-safe** and must be confined. `fastSyntaxColorRanges`
is `nonisolated` and runs off the main actor. Plan: an `actor ForkTreeSitterEngine` owns the
parsers and per-language grammars; the nonisolated scanner path calls into it. Since the current
call site is synchronous, Phase B evaluates either (a) a synchronous per-call parser guarded by an
`NVELock` (matches the existing `SyntaxRegexCache` pattern), or (b) making the highlight install
path `await` the actor. Decision made in Phase B against the real call site; (a) is lower-risk.

### Fallback contract

`ForkTreeSitterHighlighter.colorRanges` returns `nil` for any language without a loaded grammar,
or on parse failure. `fastSyntaxColorRanges` treats `nil` as "fall through to regex." So the toggle
**never breaks a language** — worst case is "same as regex."

---

## Phased rollout

| Phase | Scope | Risk |
|-------|-------|------|
| **A** | Toggle enum + `@AppStorage` + Settings picker + seam routing, **both branches = regex**. No dependency, no behavior change. | Very low — pure plumbing. |
| **B** | Add SwiftTreeSitter+Neon+tree-sitter-html; `ForkTreeSitterHighlighter` for **HTML only**; wire behind the toggle. A/B on real HTML. | Medium — first C dependency, bridging, concurrency. |
| **C** | Add CSS, XML, C grammars. Toggle + report per language. | Low per-grammar after B. |
| **D** | Decide per language which engine wins; optionally make tree-sitter default for the languages where it clearly beats regex; keep the toggle. | Low. |

Regex remains the default and the fallback throughout. Nothing is removed.

---

## Isolation (fork rules)

- New code in `Neon Vision Editor/Fork/` (`SyntaxEngine.swift`, `TreeSitterHighlighter.swift`),
  filenames without the `Fork` prefix (folder namespaces).
- Upstream touched only at the `fastSyntaxColorRanges` seam via a `// MARK: - FORK` hook + the
  Settings default registration + one Settings picker row.
- `SettingsSyntaxEngine` default registered in `NeonVisionEditorApp` per the settings-default contract.
