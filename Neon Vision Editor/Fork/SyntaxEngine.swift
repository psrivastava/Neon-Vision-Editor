//
//  SyntaxEngine.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Selectable syntax-highlighting engine (Settings → Editor). `regex` is the existing
//  NSRegularExpression tables + hand-written scanners; `treeSitter` upgrades the languages that
//  have a loaded tree-sitter grammar and falls back to regex for everything else. The toggle exists
//  so both engines can be A/B compared per language on real files.
//
//  Phase A (this commit): the enum + the accessor + the seam routing are in place, but BOTH engines
//  currently resolve to the regex path — no tree-sitter dependency yet. Flipping the toggle is a
//  no-op on output until Phase B wires the tree-sitter grammars in. Kept `nonisolated` so the
//  off-main-thread scanner (`fastSyntaxColorRanges`) can read the setting.
//

import Foundation

enum SettingsSyntaxEngine: String, CaseIterable, Sendable {
    case regex
    case treeSitter

    var displayName: String {
        switch self {
        case .regex: return "Regex (classic)"
        case .treeSitter: return "Tree-sitter (beta)"
        }
    }

    var helpText: String {
        switch self {
        case .regex:
            return "The classic per-language pattern highlighter. Fast and stable for every language."
        case .treeSitter:
            return "Structural parser for richer HTML/CSS/XML/C coloring. Falls back to Regex for languages without a grammar."
        }
    }
}

nonisolated let forkSyntaxEngineKey = "SettingsSyntaxEngine"

/// The active engine, read from UserDefaults. `nonisolated` so the syntax range-computer (which runs
/// off the main actor) can consult it. Falls back to `.regex` for a missing/unknown value.
nonisolated func forkCurrentSyntaxEngine() -> SettingsSyntaxEngine {
    let raw = UserDefaults.standard.string(forKey: forkSyntaxEngineKey) ?? SettingsSyntaxEngine.regex.rawValue
    return SettingsSyntaxEngine(rawValue: raw) ?? .regex
}
