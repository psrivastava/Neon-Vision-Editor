//
//  ChromeStyle.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Chrome surface + separator tokens (UX-F2). The reported problem: the status bar, sidebars, and
//  tab bar all paint the editor's OWN background (`editorSurfaceBackgroundStyle` →
//  `currentEditorTheme(...).background`) with `.secondary` text and no separators, so chrome blends
//  into the code canvas. These tokens give chrome a surface one step off the editor background plus
//  a visible hairline separator, so panels read as distinct surfaces (the NotepadMac `ui.statusBar`
//  / `ui.statusBarText` / `Divider()` treatment) — WITHOUT retinting the editor itself.
//
//  Isolation: this file is fork-owned. Upstream chrome sites opt in via small `// MARK: - FORK`
//  hooks that swap their `.background(editorSurfaceBackgroundStyle)` for `forkChromeSurfaceStyle`
//  and add `forkChromeTopSeparator`. The shared editor chokepoint is left untouched, so the code
//  canvas keeps the theme background.
//

import SwiftUI

extension ContentView {

    /// Surface fill for chrome (status bar, sidebars, tab bar). BOLD (MeshClaw-style): the shell wears
    /// the active theme's signature hue so switching themes visibly recolors the chrome, not just the
    /// code. When the window is translucent we keep the vibrancy but tint it, so the glass is themed
    /// too — a partially-opaque accent frost over the window's visual-effect backing.
    var forkChromeSurfaceStyle: AnyShapeStyle {
        if enableTranslucentWindow {
            // Themed frost: the bold surface at partial opacity lets the window vibrancy bleed through
            // while still carrying the theme hue (a flat material would read theme-independent).
            let frostOpacity = colorScheme == .dark ? 0.62 : 0.55
            return AnyShapeStyle(forkChromeSurfaceColor.opacity(frostOpacity))
        }
        return AnyShapeStyle(forkChromeSurfaceColor)
    }

    /// Bold chrome tone: the editor background pulled toward the theme's signature accent, so the shell
    /// visibly "wears" the theme in both light and dark. Derived from the theme, so it re-tints the
    /// moment the user switches themes. Shared with the sidebars via `forkBoldChromeSurfaceColor`.
    var forkChromeSurfaceColor: Color {
        let theme = currentEditorTheme(colorScheme: colorScheme)
        return forkBoldChromeSurfaceColor(theme: theme, colorScheme: colorScheme)
    }

    /// The theme's signature hue — the color the bold chrome (and the active-tab / status-pill accent)
    /// wears. Uses the theme's own `keyword` syntax color, the most saturated identity color across the
    /// palettes, so each theme keeps a distinct chrome character.
    var forkThemeSignatureAccent: Color {
        currentEditorTheme(colorScheme: colorScheme).syntax.keyword
    }

    /// Hairline separator color for chrome edges (top of status bar, under the tab bar, pane edges).
    /// Visible in BOTH themes — the existing 0.08–0.20 strokes disappear in one mode.
    var forkChromeSeparatorColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    /// Higher-contrast status/label text than `.secondary`. On the BOLD accent-tinted surface a plain
    /// blend of the editor text can lose contrast (the surface is no longer near-background), so we
    /// bias toward the high-contrast pole — white on dark chrome, near-black on light chrome — and only
    /// lightly soften it. Keeps ≥ 4.5:1 across the themed shells.
    var forkChromeTextColor: Color {
        let theme = currentEditorTheme(colorScheme: colorScheme)
        let pole: Color = colorScheme == .dark ? .white : .black
        // Start from the theme text, pull it toward the contrast pole so it survives the bold tint,
        // then soften a hair toward the surface so it still reads as chrome, not editor body text.
        let boosted = theme.text.forkBlended(with: pole, amount: colorScheme == .dark ? 0.35 : 0.45)
        return boosted.forkBlended(with: forkChromeSurfaceColor, amount: 0.12)
    }

    /// A 1px top separator to sit above a docked chrome bar (e.g. the status bar). Place as an overlay
    /// on the bar's top edge.
    var forkChromeTopSeparator: some View {
        Rectangle()
            .fill(forkChromeSeparatorColor)
            .frame(height: 1)
            .frame(maxWidth: .infinity, alignment: .top)
            .accessibilityHidden(true)
    }
}

/// The single source of truth for the BOLD chrome tone, as a free function so both `ContentView`
/// (status bar, tab bar) and `SidebarViews` produce the identical surface. The editor background is
/// pulled a substantial way toward the theme's signature accent (its `keyword` color), then nudged
/// lighter/darker so the chrome still separates from the code canvas beneath it.
///
/// Bold intensity: ~26% toward the accent in dark, ~20% in light — assertive enough that each theme
/// clearly "wears" its color across the shell (the MeshClaw feel), while the canvas stays the true
/// theme background. Shared by `ContentView` and `SidebarViews` (both main-actor).
@MainActor
func forkBoldChromeSurfaceColor(theme: EditorTheme, colorScheme: ColorScheme) -> Color {
    let accent = theme.syntax.keyword
    let accentAmount = colorScheme == .dark ? 0.26 : 0.20
    let tinted = theme.background.forkBlended(with: accent, amount: accentAmount)
    // Small push toward the text pole so the accent-tinted shell still reads as a distinct surface
    // above/around the editor background (dark → a touch lighter, light → a touch darker).
    return tinted.forkBlended(with: theme.text, amount: colorScheme == .dark ? 0.05 : 0.04)
}

extension Color {
    /// Linear blend toward `target` by `amount` (0…1), resolved through the platform color so it
    /// works for theme colors. Falls back to `self` if components can't be resolved.
    func forkBlended(with target: Color, amount: Double) -> Color {
        let clamped = min(1, max(0, amount))
#if os(macOS)
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(target).usingColorSpace(.sRGB) else { return self }
        return Color(
            red: Double(a.redComponent + (b.redComponent - a.redComponent) * CGFloat(clamped)),
            green: Double(a.greenComponent + (b.greenComponent - a.greenComponent) * CGFloat(clamped)),
            blue: Double(a.blueComponent + (b.blueComponent - a.blueComponent) * CGFloat(clamped))
        )
#elseif canImport(UIKit)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        guard UIColor(self).getRed(&ar, green: &ag, blue: &ab, alpha: &aa),
              UIColor(target).getRed(&br, green: &bg, blue: &bb, alpha: &ba) else { return self }
        return Color(
            red: Double(ar + (br - ar) * CGFloat(clamped)),
            green: Double(ag + (bg - ag) * CGFloat(clamped)),
            blue: Double(ab + (bb - ab) * CGFloat(clamped))
        )
#else
        return self
#endif
    }
}
