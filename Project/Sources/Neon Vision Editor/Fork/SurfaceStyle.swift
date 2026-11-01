// FORK ADDITION: A2 surface system — elevation-stepped chrome surfaces derived
// from the active editor theme (or neutral White/Grey presets). The editor pane
// stays on the theme background (lightest step); chrome steps down away from it:
// tab strip/toolbar > status bar > panels/window. Mirrors the approved A2 mockup
// in docs/fork/ui-mockups.html. Consumed via thin seams in ContentView's
// mac surface style properties and the status bar background.

import SwiftUI
#if os(macOS)
import AppKit
#endif

nonisolated enum ForkSurfacePreset: String, CaseIterable, Identifiable {
    /// Upstream behavior: fixed grayscale chrome, untouched.
    case upstream
    /// Whole-body tint derived from the active editor theme's background hue.
    case theme
    /// Neutral near-white chrome (light "paper" chrome regardless of theme).
    case white
    /// Neutral mid-grey chrome.
    case grey

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .upstream: return "Default"
        case .theme: return "Theme Tint"
        case .white: return "White"
        case .grey: return "Grey"
        }
    }

    nonisolated static let storageKey = "ForkSurfaceStylePreset"
}

/// Elevation steps, lowest (furthest from the editor) to highest.
nonisolated enum ForkSurfaceLevel {
    case panel      // sidebars, preview panes, window-level chrome
    case statusBar  // bottom status bar
    case tabStrip   // toolbar + tab strip (adjacent to the editor)
}

nonisolated enum ForkSurfaceStyle {
    /// Returns the chrome color for the given preset and elevation level, or nil
    /// when the preset is `.upstream` (caller falls through to upstream behavior).
    static func chromeColor(
        presetRaw: String,
        level: ForkSurfaceLevel,
        themeBackground: Color
    ) -> Color? {
        let preset = ForkSurfacePreset(rawValue: presetRaw) ?? .upstream
        switch preset {
        case .upstream:
            return nil
        case .white:
            return neutral(level: level, panel: 0.88, statusBar: 0.91, tabStrip: 0.945)
        case .grey:
            return neutral(level: level, panel: 0.78, statusBar: 0.82, tabStrip: 0.87)
        case .theme:
            return themeTinted(level: level, themeBackground: themeBackground)
        }
    }

    private static func neutral(
        level: ForkSurfaceLevel,
        panel: Double, statusBar: Double, tabStrip: Double
    ) -> Color {
        let white: Double
        switch level {
        case .panel: white = panel
        case .statusBar: white = statusBar
        case .tabStrip: white = tabStrip
        }
        return Color(white: white)
    }

    private static func themeTinted(level: ForkSurfaceLevel, themeBackground: Color) -> Color? {
#if os(macOS)
        guard let rgb = NSColor(themeBackground).usingColorSpace(.deviceRGB) else { return nil }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        rgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)

        let isDarkTheme = brightness < 0.5
        // Dark themes: editor is the darkest surface; chrome steps UP in
        // brightness by small additive offsets, so hue is preserved (a near-
        // black editor theme would otherwise multiply to pure black and lose
        // every trace of the theme accent).
        // Light themes: editor is the lightest; chrome steps DOWN by small
        // multiplicative factors, matching the original design.
        let chromeBrightness: CGFloat
        if isDarkTheme {
            let bump: CGFloat
            switch level {
            case .panel: bump = 0.06
            case .statusBar: bump = 0.09
            case .tabStrip: bump = 0.12
            }
            chromeBrightness = min(0.55, brightness + bump)
        } else {
            let factor: CGFloat
            switch level {
            case .panel: factor = 0.90
            case .statusBar: factor = 0.93
            case .tabStrip: factor = 0.96
            }
            chromeBrightness = max(0.02, brightness * factor)
        }
        // Keep hue legible once we move away from the base brightness. Light
        // themes get a stronger bump than dark ones because their chrome has
        // more absolute brightness to spare.
        let chromeSaturation = min(1, saturation * (isDarkTheme ? 1.1 : 1.25) + (isDarkTheme ? 0.04 : 0.02))
        return Color(
            NSColor(
                hue: hue,
                saturation: chromeSaturation,
                brightness: chromeBrightness,
                alpha: 1
            )
        )
#else
        return nil
#endif
    }

#if os(macOS)
    /// FORK shell redesign: the window-filling backdrop behind the three
    /// rounded cards. Dark themes: still darker than the editor, but only
    /// slightly, so the backdrop stays theme-tinted and doesn't collapse to
    /// pure black. Light themes: a clear step darker.
    static func shellBackdrop(themeBackground: Color, isDark: Bool) -> Color {
        let base = NSColor(themeBackground)
        let blended = base.blended(withFraction: isDark ? 0.18 : 0.10, of: .black)
        return Color(nsColor: blended ?? base)
    }

    /// FORK shell redesign: fill for the sidebar cards — one elevation step off
    /// the editor surface. Dark themes blend WHITE so the card stays lighter
    /// than the backdrop (and still carries the theme hue); light themes blend
    /// BLACK so the card sits darker than the backdrop.
    static func panelCardFill(themeBackground: Color, isDark: Bool) -> Color {
        let base = NSColor(themeBackground)
        let blended = isDark
            ? base.blended(withFraction: 0.14, of: .white)
            : base.blended(withFraction: 0.045, of: .black)
        return Color(nsColor: blended ?? base)
    }
#endif
}
