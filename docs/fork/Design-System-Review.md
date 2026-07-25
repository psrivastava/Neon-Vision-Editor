# Neon Vision Editor — Design-System Review & Unification Plan

> **Status:** Findings for review. **No code changed yet.**
> **Scope:** Fork-only (`fork/integration`), no upstream PR. All edits will be `// MARK: - FORK` tagged.
> **Method:** Baseline token inventory from source → review via the `ui-ux-pro-max` skill's **SwiftUI stack** + `pro-rules`/UX guidelines → this plan.
> **Reviewed with:** `ui-ux-pro-max` (SwiftUI stack, `--density 8 --variance 2 --motion 3`), UX guidelines (typography/consistency), and its pre-delivery checklist.

---

## 1. Baseline (measured from current source)

Token values actually in use today across the chrome surfaces (`ContentView+TabChromeStatus.swift`, `+Toolbar.swift`, `SidebarViews.swift`, `+StructuredData.swift`, `+MarkdownFormatting.swift`, `Fork/ChromeStyle.swift`):

| Dimension | Distinct values in use | Verdict |
|---|---|---|
| **Font size** | 9, 10, 11, 12, 13, 14 (6 sizes) | No modular scale |
| **Font weight** | regular, medium, semibold, bold (mixed ad hoc) | No weight system |
| **Padding** | 0, 2, 3, 4, 5, 6, 7, 8, 10, 12, 16, 18 (12 values) | Off-grid magic numbers |
| **Corner radius** | 0, 1, 2, 7, 8, 9, 12, 14 (8 values) | No radius scale |
| **Stack spacing** | 0, 2, 3, 5, 6, 8, 9, 10, 12 (9 values) | No spacing rhythm |
| **Opacity (separators/muted)** | 0.12, 0.14, 0.16, 0.18, 0.46, 0.58, 0.62, 0.70, 0.9 | Inconsistent muting |
| **Segmented-control widths** | 210, 240, 280 | Inconsistent control sizing |

**Interpretation:** every individual surface is fine, but there is no shared scale — 6 font sizes, 12 padding values, 8 radii. That lack of rhythm is what reads as "unpolished" next to NotepadMac, which commits to one scale everywhere. This is confirmed by the SwiftUI-stack guideline #16 ("Design system spacing values, not `.padding(13), .padding(17)`") and typography guideline ("consistent modular scale, not random font sizes").

---

## 2. Findings (skill-backed)

### F1 — No type scale (MEDIUM, high perceived impact)
6 font sizes × 4 weights with no system. Skill: *"Consistent type hierarchy aids scanning — use a consistent modular scale (12 14 16 18 24 32), not arbitrary sizes."*

### F2 — No spacing/padding grid (LOW severity, HIGH perceived impact)
12 padding + 9 spacing values, none on a 4-pt grid. SwiftUI guideline #16 flags this exact anti-pattern. This is the single biggest contributor to the "busy/unpolished" feel.

### F3 — No radius scale (LOW, cumulative)
8 corner-radius values (1, 2, 7, 8, 9, 12, 14…). Cards, capsules, and bars don't share a radius family.

### F4 — Inconsistent muting/separators (MEDIUM)
9 different opacity values for "secondary/muted/separator." No semantic muted/separator token — each site invents its own alpha.

### F5 — No shared control vocabulary (MEDIUM)
Segmented controls at 3 widths (210/240/280); status items, badges, and bars each set their own font/weight/color. The view-mode bar unification (done) proved the pattern — it needs to extend to all chrome.

### F6 — Interaction states not systematic (MEDIUM — checklist item)
Pre-delivery checklist: hover/focus/active states with 150–300ms transitions; visible focus rings for keyboard nav; `prefers-reduced-motion` respected (SwiftUI: `@Environment(\.accessibilityReduceMotion)`). Currently ad hoc.

### F7 — Contrast not audited (CRITICAL — checklist priority 1)
Muted text at 0.46–0.62 opacity on blended chrome surfaces may fail the 4.5:1 target in one or both themes. Must be measured, not eyeballed.

---

## 3. The plan — one token layer, applied surface-by-surface

### Phase 0 — Baseline screenshots (verification harness)
Capture current-state screenshots of each surface (toolbar, status bar, tab bar, TOC sidebar, project sidebar, view-mode bars, settings) in **light + dark** at representative window sizes, using the `visual-review` skill. These are the "before" images every later phase diffs against.

### Phase 1 — Define the token layer (no visual change yet)
Extend `Fork/ChromeStyle.swift` (or a new `Fork/DesignTokens.swift`) with one source of truth, exposed as SwiftUI helpers / a `ViewModifier` set (SwiftUI guideline #19):

- **Type ramp** (semantic, not raw sizes): `chromeCaption` 11, `chromeBody` 12, `chromeTitle` 13, plus weight rules (metadata = medium, headers = semibold). Editor/mono text unchanged.
- **Spacing scale**: 2, 4, 8, 12, 16 (4-pt grid). Everything snaps to these.
- **Radius scale**: `small` 6, `medium` 10, `large` 14.
- **Semantic colors** (already partly in ChromeStyle): `surface`, `separator`, `textPrimary`, `textSecondary`, `accent` — one definition, theme-aware, contrast-checked.
- **Control tokens**: one segmented-control height + a single width policy.
- **Motion**: one `chromeTransition` (≈200ms ease) gated on `accessibilityReduceMotion`.

### Phase 2 — Apply to ONE surface + before/after
Start with the **status bar + view-mode bars** (freshest, most self-contained). Convert to the tokens, screenshot **after**, run `visual-review` against the checklist, and show you before/after side-by-side. **Stop here for sign-off** on the direction before touching anything else.

### Phase 3 — Roll out (after approval)
Apply the same tokens to tab bar → both sidebars → toolbar → settings, one surface per step, screenshot each. Run the `pro-rules` pre-delivery checklist as the exit gate.

### Phase 4 — Contrast + a11y pass
Measure muted-text contrast (F7) in both themes, fix any < 4.5:1; verify focus rings and reduced-motion (F6).

---

## 4. Direction decision — CHOSEN: (B) NVE's own identity

**Decided:** Direction **(B)** — NVE gets its own consistent identity: the same discipline as a
polished reference (one scale, one control vocabulary) with a distinct personality, rather than
copying NotepadMac.

Key call for a **themeable** editor: the disciplined "own identity" is **one consistent STRUCTURE
applied over whatever theme is active**, not one hardcoded palette. So:
- **Structure is absolute** (type ramp, 4-pt spacing grid, radius family, control height, motion) —
  identical on every surface, every theme. This is where the polish comes from.
- **Color stays theme-derived** (via `ChromeStyle.swift`) — a fixed dark-slate/green palette would
  fight the user's chosen theme + light/dark. The identity is the *consistent use* of one accent
  and one surface-derivation rule, not a frozen set of hex values.

### Phase 1 — DONE (token layer, no visual change)
`Fork/DesignTokens.swift` created (additive; nothing consumes it yet):
- `ForkDesign.Space` — 2/4/8/12/16/24 (4-pt grid)
- `ForkDesign.Radius` — small 6 / medium 10 / large 14
- `ForkDesign.Text` — caption 11 / body 12 / title 13, semantic weights (mono/editor text untouched)
- `ForkDesign.Control` — height 22, segmented max-width 220 (was 210/240/280)
- `ForkDesign.Motion` — one 200ms ease, `forkChromeAnimation(reduceMotion)` collapses to nil
- Semantic color aliases on `ContentView` (`forkTextPrimary` / `forkTextSecondary` / `forkAccent`)
  that map onto the existing contrast-checked `ChromeStyle` tokens — no new colors, one source.

Editor/document text styling remains OUT OF SCOPE.

---

## 5. Guardrails
- Fork-only; every upstream edit `// MARK: - FORK` tagged; new tokens live in `Fork/`.
- Deploy after each phase via `scripts/fork/build-and-deploy.sh` (hash-verified `/Applications/nve.app`).
- No commit/push without explicit go-ahead.
- Editor/document text styling is **out of scope** — this pass is chrome only.
