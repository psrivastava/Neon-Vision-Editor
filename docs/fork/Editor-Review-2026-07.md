# Neon Vision Editor — Editor Subsystem Review (2026-07)

Step-back review of the `fork/integration` editor changes on top of upstream baseline
`05b710d2`, plus a syntax-coloring legibility review and a parsing/library assessment.
Three tracks: **implementation health**, **coloring**, **parsing**.

---

## Verdict

The chrome, CSV rainbow, tiered status bar, unified view-mode bar, and threshold settings are
coherent and low-risk. The complexity — and the real bugs — are concentrated in **one subsystem:
the large-file / highlight-gating logic** added by the auto-mode work (`3f8a5a51`).

Normal small-file editing is **not** at risk: large-file mode requires ≥300 K UTF-16, so a 5 KB
source file never enters viewport-limiting, plain-text, or the fork gates. But three genuine bugs
and a tangled five-predicate gating layer need consolidation before more is built on top.

---

## Track 1 — Implementation health

### HIGH

- **H1 — per-document mode override lost on tab switch.** `forkAutoModeDecidedForResourceID` is a
  single scalar, not a per-resource set. Override tab A → Standard, switch to B, switch back to A →
  A silently resets to the auto pick. Contradicts the documented "explicit pick lasts for the
  current document." Fix: track decided resources in a `Set<String>` (or a per-resource override
  map).
- **H2 — mode written to a *persisted* `@AppStorage` key despite "no persistence" intent.**
  `largeFileOpenModeRaw` is `@AppStorage("SettingsLargeFileOpenMode")`; `forkApplyAuto…` writes it
  on every open/tab-switch, for every file including small ones. The last huge file's forced
  `plainText` bleeds into the next launch as a wrong initial mode / flash. Fix: guard the auto-apply
  on `effectiveLargeFileModeEnabled` (small files never touch it) and reset the key to the auto
  default on the fresh-load path so it can't persist a stale forced mode.
- **H3 — JSON 400 K–1.2 M highlights on open but goes stale on scroll.** `forkEffectiveLargeFileHighlight`
  (OR of the two paths) lets a 500 K JSON get an initial viewport pass, but
  `forkLargeFileSupportsPerScrollRehighlight` is the 400 K-capped predicate, so scrolling leaves
  stale regions. Resolved by the `HighlightStrategy` consolidation (below).

### MEDIUM

- **M1 — duplicated ceiling representation.** The non-JSON ceiling exists three ways:
  `EditorRuntimeLimits.forkNonJSONLargeFileHighlightUTF16Length` (const),
  `forkNonJSONHighlightLimit()` (**dead — zero callers**), and `forkNonJSONHighlightMaxRaw`
  (`@AppStorage`, the one actually used). Consolidate; delete the dead func.
- **M2 — `forkLargeFileViewportHighlightAllowed` ignores its `language` arg and the configured
  ceiling in `.deferred`** (returns `true` at any size). Only `preferredHighlightRange`'s viewport
  clamp saves perf. Fold into the strategy computation.
- **M3 — five overlapping "can this highlight?" predicates** across 4 files
  (`supportsResponsiveLargeFileHighlight` ×2, `forkLargeFileViewportHighlightAllowed`,
  `forkEffectiveLargeFileHighlight`, `forkLargeFileSupportsPerScrollRehighlight`). Collapse into one
  `enum HighlightStrategy { off, viewportOnce, viewportPerScroll, full }` computed once from
  (language, length, mode). This is the single biggest maintainability lever and it resolves H3/M1/M2.

### LOW

- **L1 — dead CSV regex branch** in `SyntaxHighlighting.swift` (`case "csv"`), now unreachable since
  CSV routes to `forkCSVRainbowColorRanges`. Note: all CSVs (incl. tiny) now render rainbow — that's
  intended, confirm as default.
- **L2 — pre-existing `.htmlFast` dead branch** (reduced HTML regex map) — unreachable, predates the
  fork. Remove.
- **L3 — `previewSegmentLabel` redundant branch** — both cases return "Rendered".

**Concurrency:** the new `nonisolated` CSV/palette code is correct (operates on passed `NSString` +
`Sendable SyntaxColors`; reads only `let Color` fields).

---

## Track 2 — Coloring (legibility)

The editor **background and base text are luminance-normalized per light/dark mode**
(`modeAdjustedEditorBackground` / `modeAdjustedEditorText` in `ThemeSettings.swift`), but the
**individual syntax token colors** (keyword/string/number/comment across all 28 palettes) are **not**
contrast-adjusted against that shifted background. A bright token on a mode-lightened background can
fall below WCAG 4.5:1 — a systematic legibility gap, worst in light mode on the neon themes.
Comments (deliberately dim) are the worst offender.

Fix: run token colors through the same mode-adjustment the base text already gets, with a contrast
floor built on the existing `relativeLuminance` helper.

---

## Track 3 — Parsing & library assessment

**Today:** language detected by extension/heuristic → per-language `NSRegularExpression` tables +
hand-written scanners (HTML, JSON, CSV). Rich: Swift, TypeScript, Markdown, YAML, PHP.
**Weak: HTML** (fast scanner colors the whole `<…>` span one color — no tag/attr/value/comment
distinction), **CSS** (3 patterns), **C/C++** (minimal). Regex can't express nesting (CSS/JS in HTML)
or recover from malformed markup — this is the "HTML hardly parses" report.

**Recommendation: adopt tree-sitter for highlighting only** — SwiftTreeSitter + Neon (BSD-3,
ChimeHQ), layered onto the existing `NSTextView`/`UITextView`, no editor rewrite. Industry standard
(Zed, Neovim, GitHub, Nova by Panic), pure C, MIT, notarization-clean, incremental/error-tolerant,
license-compatible with Apache-2.0. **Reject** Runestone (iOS/Catalyst-only, full editor) and
STTextView (GPL/commercial — hard license blocker). Highlightr (highlight.js) is unmaintained as of
2026 — stopgap at best. Effort: 2–4 weeks; budget for UTF-16↔byte-range bridging and Swift-6 actor
confinement of the parser. **This is a separate effort**, tracked as a plan, not part of the quick
fixes.

---

## Sequencing

1. **Quick (this pass):** confirm & fix current-line/region regression; H1; H2; delete dead code
   (L1/L2/L3).
2. **Medium (this pass):** `HighlightStrategy` consolidation (resolves H3/M1/M2/M3); coloring
   contrast pass.
3. **Large (separate effort):** tree-sitter adoption plan for real language support.

---

## Open items (post-checkpoint)

- **Region + current-line highlight do not work for HTML / XML.** Root cause: the scope-region
  matcher (`computeBracketScopeMatch`) only pairs `{ } ( ) [ ]`; HTML/XML nest with `<tag>…</tag>`,
  so nothing matches. Current-line also reads as absent on these because they open in a non-source
  view by default. Fix: teach the scope matcher `<tag>` pairs for HTML/XML (and confirm current-line
  applies in Source view). Deferred at the 2026-07 checkpoint; token-coloring work comes first.
- **Token coloring is thin for HTML/CSS/XML** even after the WCAG-floor revert — the regex tables
  barely distinguish tag/attr/value. This is the tree-sitter driver. A WCAG contrast floor was tried
  and reverted: blending tokens toward black/white to hit 4.5:1 desaturated the vivid palettes. Any
  retry must operate in HSL (lift lightness, preserve hue/saturation), not blend to gray.
