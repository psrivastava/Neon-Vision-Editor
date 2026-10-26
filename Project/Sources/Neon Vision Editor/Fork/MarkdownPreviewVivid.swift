//
//  MarkdownPreviewVivid.swift
//  Neon Vision Editor — FORK ADDITION
//
//  "Vivid" markdown preview template (Batch C, task 9 — theming parity with NotepadMac).
//  Keeps NVE's clean `default` document palette as the base, then tints the prose chrome
//  (headings, links, inline code, quote bar) with colors pulled LIVE from the active editor
//  theme (`themePaletteColors(for: SettingsThemeName)`). Because it reads the theme palette,
//  the preview re-colors whenever the user switches editor themes — the "colorful" NotepadMac feel.
//
//  Isolation: all color logic lives here. Upstream `ContentView+MarkdownPreviewExport.swift` needs
//  only two one-line `// FORK` hooks — a template-list entry and a `templateAccentCSS` switch case.
//  Code-block syntax coloring (the `syntax-*` spans) is untouched; only prose chrome changes.
//

import SwiftUI

extension ContentView {

    /// CSS overrides for the "vivid" template. Layered AFTER the base rules in `markdownPreviewCSS`,
    /// so these equal-specificity rules win. Reads the active theme palette so headings/links/etc.
    /// track the editor's current color scheme.
    ///
    /// - Parameter preferDarkMode: forwarded from `markdownPreviewCSS` so tints can adapt if needed.
    func forkVividAccentCSS(preferDarkMode: Bool) -> String {
        let name = canonicalThemeName(UserDefaults.standard.string(forKey: "SettingsThemeName") ?? "Neon Glow")
        let palette = themePaletteColors(for: name)

        // Map editor-theme roles → preview prose roles (mirrors NotepadMac's mapping).
        let heading = forkCSSHex(palette.keyword)   // h1–h6
        let link = forkCSSHex(palette.type)         // a (closest to NotepadMac's "function")
        let inlineCode = forkCSSHex(palette.string) // inline `code`
        let quote = forkCSSHex(palette.keyword)     // blockquote left bar

        return """
        h1, h2, h3, h4, h5, h6 { color: \(heading); }
        h1 { border-bottom-color: color-mix(in srgb, \(heading) 30%, transparent); }
        h2 { border-bottom-color: color-mix(in srgb, \(heading) 22%, transparent); }
        strong { color: color-mix(in srgb, \(heading) 55%, currentColor); }
        a { color: \(link); border-bottom-color: color-mix(in srgb, \(link) 45%, transparent); }
        /* Inline code only — code blocks keep their syntax-* span coloring untouched. */
        :not(pre) > code { color: \(inlineCode); }
        blockquote { border-left-color: \(quote); }
        """
    }
}

/// Convert a SwiftUI `Color` to a `#rrggbb` string for embedding in generated CSS.
/// Falls back to a neutral gray if the platform can't resolve sRGB components.
nonisolated func forkCSSHex(_ color: Color) -> String {
    func clampByte(_ value: CGFloat) -> Int {
        Int((min(1, max(0, value)) * 255).rounded())
    }
#if os(macOS)
    guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return "#808080" }
    let r = clampByte(srgb.redComponent)
    let g = clampByte(srgb.greenComponent)
    let b = clampByte(srgb.blueComponent)
#elseif canImport(UIKit)
    var rC: CGFloat = 0, gC: CGFloat = 0, bC: CGFloat = 0, aC: CGFloat = 0
    guard UIColor(color).getRed(&rC, green: &gC, blue: &bC, alpha: &aC) else { return "#808080" }
    let r = clampByte(rC)
    let g = clampByte(gC)
    let b = clampByte(bC)
#else
    let r = 128, g = 128, b = 128
#endif
    return String(format: "#%02x%02x%02x", r, g, b)
}
