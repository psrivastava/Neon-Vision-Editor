//
//  DesignTokens.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Phase 1 of the design-system unification pass (docs/fork/Design-System-Review.md).
//  ONE source of truth for chrome structure. Baseline inventory found 6 font sizes, 4 ad-hoc
//  weights, 12 padding values, 8 corner radii, 9 muting opacities, and 3 control widths across the
//  chrome surfaces — no shared scale. That scatter is what reads as "unpolished." These tokens
//  replace the magic numbers with one modular scale (SwiftUI stack guideline #16: "design-system
//  spacing values, not .padding(13)/.padding(17)"; typography: "consistent modular scale").
//
//  DIRECTION B — "NVE's own identity": the STRUCTURE (type ramp, spacing grid, radius family,
//  control height, motion) is absolute and identical everywhere. COLOR stays theme-derived (see
//  ChromeStyle.swift) because NVE ships many user themes + light/dark — a hardcoded palette would
//  fight the user's chosen theme. Discipline = one consistent structure over any theme, not one
//  fixed set of colors.
//
//  ADDITIVE ONLY: nothing consumes these yet. Phase 2 migrates the status bar + view-mode bars to
//  them behind a before/after review; Phase 3 rolls out to the remaining surfaces. Editor/document
//  text styling is OUT OF SCOPE — chrome only.
//

import SwiftUI

// MARK: - Structural tokens (absolute; theme-independent)

/// Fork chrome design tokens. Namespaced under `Fork` so it never collides with upstream.
enum ForkDesign {

    // MARK: Spacing — 4-pt grid. Every chrome padding/gap snaps to one of these.
    enum Space {
        static let xxs: CGFloat = 2   // hairline gaps only
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    // MARK: Corner radius — one family (was 1/2/7/8/9/12/14).
    enum Radius {
        static let small: CGFloat = 6    // chips, segmented controls, small buttons
        static let medium: CGFloat = 10  // cards, popovers, bars
        static let large: CGFloat = 14   // large surfaces / sheets
    }

    // MARK: Type ramp — chrome text only (editor/mono text is unchanged).
    // Semantic sizes, not raw numbers (was 9/10/11/12/13/14 mixed with 4 weights).
    enum Text {
        /// 11pt — captions, badges, muted metadata.
        static func caption(_ weight: Font.Weight = .medium) -> Font { .system(size: 11, weight: weight) }
        /// 12pt — default chrome body: status items, control labels.
        static func body(_ weight: Font.Weight = .medium) -> Font { .system(size: 12, weight: weight) }
        /// 13pt — chrome titles / section headers in panels.
        static func title(_ weight: Font.Weight = .semibold) -> Font { .system(size: 13, weight: weight) }

        // Raw sizes exposed for the rare NSFont/UIFont bridge site that can't take a `Font`.
        static let captionSize: CGFloat = 11
        static let bodySize: CGFloat = 12
        static let titleSize: CGFloat = 13
    }

    // MARK: Controls — one height + one segmented-control width policy (was 210/240/280).
    enum Control {
        /// Standard small-control height for chrome (segmented pickers, compact buttons).
        static let height: CGFloat = 22
        /// One max width for inline segmented view-mode controls.
        static let segmentedMaxWidth: CGFloat = 220
    }

    // MARK: Motion — one chrome transition, reduced-motion aware (see `forkChromeAnimation`).
    enum Motion {
        static let duration: Double = 0.20   // 150–300ms band (checklist)
    }
}

// MARK: - Motion helper (respects Reduce Motion)

extension View {
    /// The single chrome transition. Collapses to no animation when Reduce Motion is on.
    /// Usage: `.animation(forkChromeAnimation(reduceMotion), value: someState)`.
    func forkChromeAnimated(_ reduceMotion: Bool, value: some Equatable) -> some View {
        animation(reduceMotion ? nil : .easeOut(duration: ForkDesign.Motion.duration), value: value)
    }
}

/// The chrome animation, or `nil` under Reduce Motion. Free function for call sites that already
/// hold `@Environment(\.accessibilityReduceMotion)`.
func forkChromeAnimation(_ reduceMotion: Bool) -> Animation? {
    reduceMotion ? nil : .easeOut(duration: ForkDesign.Motion.duration)
}

// MARK: - Semantic color accessors (theme-derived; thin wrappers over ChromeStyle)
//
// These give the rest of the fork a stable vocabulary that maps onto the existing, contrast-checked
// ChromeStyle tokens — so Phase 2/3 call sites read as `forkTextSecondary` etc. rather than
// re-deriving blends. Adding new names here (not new colors) keeps ChromeStyle the single source.

extension ContentView {
    /// Primary chrome text (full-strength legible label). Alias of the contrast-checked chrome text.
    var forkTextPrimary: Color { forkChromeTextColor }

    /// Secondary chrome text — one muted step (replaces the ad-hoc 0.46–0.70 opacities). Kept ≥ the
    /// contrast floor by blending only lightly further toward the surface.
    var forkTextSecondary: Color {
        forkChromeTextColor.forkBlended(with: forkChromeSurfaceColor, amount: 0.22)
    }

    /// Accent for the single "active/selected" chrome affordance (active tab, status pill, Vim
    /// indicator). BOLD chrome: this tracks the active theme's signature hue so the accent family
    /// moves with the theme alongside the shell tint, rather than the system tint. Direction B —
    /// consistent *use* of one accent, sourced from the theme.
    var forkAccent: Color { forkThemeSignatureAccent }
}
