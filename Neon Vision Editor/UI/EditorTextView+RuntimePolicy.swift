import SwiftUI
import Foundation
import OSLog

nonisolated let syntaxHighlightSignposter = OSSignposter(subsystem: "h3p.Neon-Vision-Editor", category: "SyntaxHighlight")

#if os(macOS)
extension Notification.Name {
    static let editorPointerInteraction = Notification.Name("NeonEditorPointerInteraction")
}

enum MacEditorContentInstallRefreshPolicy {
    // A full TextKit pass repairs stale glyph maps after a document swap, but it is
    // disproportionately expensive for larger documents. Those use visible-range refreshes.
    static let fullLayoutMaxUTF16Length = 120_000

    static func shouldInvalidateFullRange(textLength: Int) -> Bool {
        textLength <= fullLayoutMaxUTF16Length
    }
}
#endif

enum EditorRuntimeLimits {
    // Above this, keep editing responsive by skipping regex-heavy syntax passes.
    static let syntaxMinimalUTF16Length = 1_200_000
    static let ultraLargeResponsiveSyntaxUTF16Length = 400_000
    // FORK: non-JSON large files have no fast tokenizer or per-frame token budget (JSON does), so
    // their viewport regex pass is far more expensive. Cap them lower than the JSON ceiling above.
    static let forkNonJSONLargeFileHighlightUTF16Length = 250_000
    static let htmlFastProfileUTF16Length = 250_000
    static let csvFastProfileUTF16Length = 120_000
    static let jsonFastProfileUTF16Length = 120_000
    static let largeFileJSONVisiblePaddingUTF16 = 2_400
    static let largeFileJSONIncrementalPaddingUTF16 = 800
    nonisolated static let largeFileJSONTokenBudgetSeconds = 0.0035
    static let csvFastProfileLongLineUTF16 = 4_000
    static let csvFastProfileScanLimitUTF16 = 120_000
    static let scopeComputationMaxUTF16Length = 300_000
    static let cursorRehighlightMaxUTF16Length = 220_000
    static let nonImmediateHighlightMaxUTF16Length = 220_000
    static let bindingDebounceUTF16Length = 250_000
    static let bindingDebounceDelay: TimeInterval = 0.18
    static let bracketScopeNearestFallbackWindowUTF16 = 8_000
}

func shouldUseCSVFastProfile(_ nsText: NSString) -> Bool {
    if nsText.length >= EditorRuntimeLimits.csvFastProfileUTF16Length {
        return true
    }
    let scanLimit = min(nsText.length, EditorRuntimeLimits.csvFastProfileScanLimitUTF16)
    guard scanLimit > 0 else { return false }
    var currentLineLength = 0
    for idx in 0..<scanLimit {
        let codeUnit = nsText.character(at: idx)
        if codeUnit == 10 {
            currentLineLength = 0
            continue
        }
        currentLineLength += 1
        if currentLineLength >= EditorRuntimeLimits.csvFastProfileLongLineUTF16 {
            return true
        }
    }
    return false
}

nonisolated func isJSONLikeLanguage(_ language: String) -> Bool {
    switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "json", "jsonc", "json5", "ipynb":
        return true
    default:
        return false
    }
}

func syntaxProfile(for language: String, text: NSString) -> SyntaxPatternProfile {
    let lower = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if lower == "html" && text.length >= EditorRuntimeLimits.htmlFastProfileUTF16Length {
        return .htmlFast
    }
    if lower == "csv" && shouldUseCSVFastProfile(text) {
        return .csvFast
    }
    if isJSONLikeLanguage(lower) && text.length >= EditorRuntimeLimits.jsonFastProfileUTF16Length {
        return .jsonFast
    }
    return .full
}

enum SyntaxFontEmphasis: Sendable {
    case keyword
    case comment
}

#if os(macOS)
func fontWithSymbolicTrait(_ font: NSFont, trait: NSFontDescriptor.SymbolicTraits) -> NSFont {
    let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait))
    guard let adjustedFont = NSFont(descriptor: descriptor, size: font.pointSize) else {
        return font
    }
    return adjustedFont
}
#else
func fontWithSymbolicTrait(_ font: UIFont, trait: UIFontDescriptor.SymbolicTraits) -> UIFont {
    guard let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(trait)) else {
        return font
    }
    return UIFont(descriptor: descriptor, size: font.pointSize)
}
#endif

func supportsResponsiveLargeFileHighlight(language: String) -> Bool {
    isJSONLikeLanguage(language) &&
        currentLargeFileSyntaxHighlightMode() == .minimal &&
        currentLargeFileOpenMode() != .plainText
}

func supportsResponsiveLargeFileHighlight(language: String, textLength: Int) -> Bool {
    textLength <= EditorRuntimeLimits.ultraLargeResponsiveSyntaxUTF16Length &&
        supportsResponsiveLargeFileHighlight(language: language)
}

// MARK: - FORK — one highlight strategy, computed once
//
// Previously five overlapping predicates (`supportsResponsiveLargeFileHighlight` ×2,
// `forkLargeFileViewportHighlightAllowed`, `forkEffectiveLargeFileHighlight`,
// `forkLargeFileSupportsPerScrollRehighlight`) decided "can this large file highlight, and how" —
// spread across four files and mutually inconsistent (a JSON 400K–1.2M highlighted on open but went
// stale on scroll because two of them disagreed on the cap). This enum is the single source of
// truth; the consumed predicates below are thin wrappers over it.
//
// Upstream only permits JSON-family large files to highlight; the fork extends the SAME
// viewport-bounded path to any language so the open-mode picker works for e.g. large XML. The
// highlight is still range-limited to the viewport (see `preferredHighlightRange`) and runs off the
// main thread; genuinely huge files are protected by that viewport clamp, not by suppression here.
enum HighlightStrategy: Sendable {
    case off                // no syntax coloring (Plain Text, or highlighting mode off)
    case viewportOnce       // one-shot viewport pass; NOT re-run on scroll (non-JSON: regex too costly per frame)
    case viewportPerScroll  // viewport pass, safely re-run on every scroll (JSON fast path: tokenizer + per-frame budget)
    case full               // full-document pass (Standard: the explicit "may be slow" choice)
}

/// The single decision for how a large file should highlight, from (language, size, open mode,
/// syntax mode). The configurable non-JSON ceiling governs only the AUTO mode pick at open
/// (see `forkAutoSelectedLargeFileMode`) — it must NOT veto an explicit override, so it is not
/// re-applied here; the active open mode is honored directly.
func forkHighlightStrategy(language: String, textLength: Int) -> HighlightStrategy {
    guard currentLargeFileSyntaxHighlightMode() == .minimal else { return .off }
    switch currentLargeFileOpenMode() {
    case .plainText:
        return .off
    case .standard:
        // Full document, capped only by the hard minimal-syntax ceiling so it never attempts a
        // truly gigantic full pass.
        return textLength <= EditorRuntimeLimits.syntaxMinimalUTF16Length ? .full : .off
    case .deferred:
        // Viewport-limited. JSON has a fast tokenizer + per-frame token budget, so it re-highlights
        // per scroll (this also fixes the old 400K-cap mismatch that left mid-size JSON stale on
        // scroll). Non-JSON gets a one-shot viewport pass — re-running the regex every scroll frame
        // is what made large non-JSON files sluggish.
        return isJSONLikeLanguage(language) ? .viewportPerScroll : .viewportOnce
    }
}

// FORK: the effective "may this large file highlight (viewport-limited or full)?" gate. Call sites
// consult this instead of `supportsResponsiveLargeFileHighlight(language:textLength:)` so non-JSON
// languages (XML, etc.) also honor the open-mode picker while keeping the JSON fast paths intact.
func forkEffectiveLargeFileHighlight(language: String, textLength: Int) -> Bool {
    forkHighlightStrategy(language: language, textLength: textLength) != .off
}

// FORK: true only when scrolling should re-run the highlight — the JSON-family fast path. Non-JSON
// large files get a one-shot viewport pass on open / mode-switch and are left alone while scrolling.
func forkLargeFileSupportsPerScrollRehighlight(language: String, textLength: Int) -> Bool {
    forkHighlightStrategy(language: language, textLength: textLength) == .viewportPerScroll
}

// MARK: - FORK — user-configurable thresholds (Settings → Editor Behavior → Performance)
//
// Stored as a UTF-16 length in UserDefaults. A stored value of 0 means "no limit — apply to the
// whole document". Missing key falls back to the built-in default.

let forkOutlineLimitKey = "SettingsForkOutlineMaxUTF16"

/// Ceiling (UTF-16 length) below which the document outline (TOC) is built. 0 = unlimited.
func forkOutlineContentLimit() -> Int {
    guard let raw = UserDefaults.standard.object(forKey: forkOutlineLimitKey) as? Int else {
        return 400_000
    }
    return raw <= 0 ? Int.max : raw
}

enum LargeFileSyntaxHighlightMode: String {
    case off
    case minimal
}

enum LargeFileOpenMode: String {
    case standard
    case deferred
    case plainText
}

func currentLargeFileSyntaxHighlightMode() -> LargeFileSyntaxHighlightMode {
    let raw = UserDefaults.standard.string(forKey: "SettingsLargeFileSyntaxHighlighting") ?? "minimal"
    return LargeFileSyntaxHighlightMode(rawValue: raw) ?? .minimal
}

func currentLargeFileOpenMode() -> LargeFileOpenMode {
    let raw = UserDefaults.standard.string(forKey: "SettingsLargeFileOpenMode") ?? "deferred"
    return LargeFileOpenMode(rawValue: raw) ?? .deferred
}

func shouldUseChunkedLargeFileInstall(isLargeFileMode: Bool, textLength: Int) -> Bool {
    guard isLargeFileMode else { return false }
    guard currentLargeFileOpenMode() != .standard else { return false }
    return textLength >= EditorRuntimeLimits.syntaxMinimalUTF16Length
}

func editorCaretLineColumn(in text: NSString, location rawLocation: Int) -> (line: Int, column: Int) {
    let location = min(max(0, rawLocation), text.length)
    var line = 1
    var lineStart = 0
    if location > 0 {
        for index in 0..<location where text.character(at: index) == 10 {
            line += 1
            lineStart = index + 1
        }
    }
    return (line, location - lineStart + 1)
}

nonisolated func isJSONWhitespace(_ codeUnit: unichar) -> Bool {
    codeUnit == 32 || codeUnit == 9 || codeUnit == 10 || codeUnit == 13
}

nonisolated func isJSONDigit(_ codeUnit: unichar) -> Bool {
    codeUnit >= 48 && codeUnit <= 57
}

nonisolated func isJSONLetter(_ codeUnit: unichar) -> Bool {
    (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122)
}

nonisolated func isJSONLiteral(_ text: NSString, range: NSRange, literal: [unichar]) -> Bool {
    guard range.length == literal.count else { return false }
    for offset in 0..<literal.count where text.character(at: range.location + offset) != literal[offset] {
        return false
    }
    return true
}
