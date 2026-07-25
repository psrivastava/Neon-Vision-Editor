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

    /// Surface fill for chrome (status bar, sidebars, tab bar). One step off the editor background so
    /// chrome is visually distinct. Respects translucency: when the window is translucent we lean on
    /// a material rather than a flat tint so the vibrancy is preserved.
    var forkChromeSurfaceStyle: AnyShapeStyle {
#if os(macOS)
        if enableTranslucentWindow {
            // A slightly stronger material than the editor's so chrome still separates over vibrancy.
            return AnyShapeStyle(.regularMaterial)
        }
        return AnyShapeStyle(forkChromeSurfaceColor)
#else
        if enableTranslucentWindow {
            return AnyShapeStyle(.thinMaterial)
        }
        return AnyShapeStyle(forkChromeSurfaceColor)
#endif
    }

    /// Solid chrome tone: the editor background nudged toward the foreground text, so it reads as a
    /// separate surface in both light and dark themes (dark → slightly lighter, light → slightly
    /// darker). Derived from the theme so it stays correct when the user switches themes.
    var forkChromeSurfaceColor: Color {
        let theme = currentEditorTheme(colorScheme: colorScheme)
        let base = theme.background
        let tint = theme.text
        // 8% toward text in dark, 6% in light — enough to separate, not enough to look like a panel.
        let amount = colorScheme == .dark ? 0.08 : 0.06
        return base.forkBlended(with: tint, amount: amount)
    }

    /// Hairline separator color for chrome edges (top of status bar, under the tab bar, pane edges).
    /// Visible in BOTH themes — the existing 0.08–0.20 strokes disappear in one mode.
    var forkChromeSeparatorColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.12)
    }

    /// Higher-contrast status/label text than `.secondary` (which fails 4.5:1 on the blended surface).
    var forkChromeTextColor: Color {
        let theme = currentEditorTheme(colorScheme: colorScheme)
        // Editor foreground softened ~30% toward the surface — legible but still secondary-feeling.
        return theme.text.forkBlended(with: forkChromeSurfaceColor, amount: 0.30)
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
