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

// MARK: - FORK — large-file open-mode divergence
//
// Upstream only permits *JSON-family* large files to highlight (viewport-limited); every other
// language is suppressed in large-file mode, so Standard / Responsive / Plain Text look identical
// for e.g. a large XML — the open-mode picker appears to do nothing.
//
// This predicate extends the SAME viewport-bounded highlight path to any language when the file is
// under the responsive cap and the mode isn't Plain Text. It deliberately reuses
// `ultraLargeResponsiveSyntaxUTF16Length` as the ceiling so genuinely huge files stay unhighlighted
// for performance — the highlight itself is still range-limited to the viewport (see
// `preferredHighlightRange`) and runs off the main thread. Plain Text short-circuits to `false`,
// which is what makes it visibly differ from Standard / Responsive.
func forkLargeFileViewportHighlightAllowed(language: String, textLength: Int) -> Bool {
    // The non-JSON highlight ceiling governs only the AUTO mode pick (Responsive vs Plain Text at
    // open) — it must NOT veto an explicit user override. Here we honor whatever mode is active:
    //   • Plain Text → no highlighting.
    //   • Responsive → viewport-limited highlighting, cheap at any size (only the visible region).
    //   • Standard   → full-document highlighting; the explicit "may be slow" choice, capped only by
    //     the hard upstream minimal-syntax ceiling so it never attempts a truly gigantic full pass.
    guard currentLargeFileSyntaxHighlightMode() == .minimal else { return false }
    switch currentLargeFileOpenMode() {
    case .plainText:
        return false
    case .standard:
        return textLength <= EditorRuntimeLimits.syntaxMinimalUTF16Length
    case .deferred:
        return true
    }
}

// FORK (#2): true only for the JSON-family fast path, which safely re-highlights on every scroll
// (fast tokenizer + per-frame token budget). Non-JSON large files must NOT re-highlight per scroll —
// they get a one-shot viewport pass on open / mode-switch and are left alone while scrolling.
func forkLargeFileSupportsPerScrollRehighlight(language: String, textLength: Int) -> Bool {
    supportsResponsiveLargeFileHighlight(language: language, textLength: textLength)
}

// MARK: - FORK — user-configurable thresholds (Settings → Editor Behavior → Performance)
//
// Both are stored as a UTF-16 length in UserDefaults. A stored value of 0 means "no limit —
// apply to the whole document". Missing key falls back to the built-in default.

let forkNonJSONHighlightLimitKey = "SettingsForkNonJSONHighlightMaxUTF16"
let forkOutlineLimitKey = "SettingsForkOutlineMaxUTF16"

/// Ceiling (UTF-16 length) below which non-JSON large files may viewport-highlight. 0 = unlimited.
func forkNonJSONHighlightLimit() -> Int {
    guard let raw = UserDefaults.standard.object(forKey: forkNonJSONHighlightLimitKey) as? Int else {
        return EditorRuntimeLimits.forkNonJSONLargeFileHighlightUTF16Length
    }
    return raw <= 0 ? Int.max : raw
}

/// Ceiling (UTF-16 length) below which the document outline (TOC) is built. 0 = unlimited.
func forkOutlineContentLimit() -> Int {
    guard let raw = UserDefaults.standard.object(forKey: forkOutlineLimitKey) as? Int else {
        return 400_000
    }
    return raw <= 0 ? Int.max : raw
}

// FORK: the effective "may this large file highlight (viewport-limited)?" gate. Upstream call sites
// consult this instead of `supportsResponsiveLargeFileHighlight(language:textLength:)` so non-JSON
// languages (XML, etc.) also honor the open-mode picker while keeping the JSON fast paths intact.
func forkEffectiveLargeFileHighlight(language: String, textLength: Int) -> Bool {
    supportsResponsiveLargeFileHighlight(language: language, textLength: textLength) ||
        forkLargeFileViewportHighlightAllowed(language: language, textLength: textLength)
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
