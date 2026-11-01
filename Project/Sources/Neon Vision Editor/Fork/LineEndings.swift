//
//  LineEndings.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Line-ending detection and conversion (LF / CRLF / CR). NVE already *displays* the detected
//  line ending in the status bar (ContentView+TabChromeStatus.lineEndingStatusText); this adds the
//  missing *conversion* half (task 7).
//
//  Pure and Sendable — test-target-safe, no editor/UI dependency.
//

import Foundation

public enum ForkLineEnding: String, CaseIterable, Sendable {
    case lf   // "\n"   — Unix / macOS
    case crlf // "\r\n" — Windows
    case cr   // "\r"   — classic Mac

    public var literal: String {
        switch self {
        case .lf: return "\n"
        case .crlf: return "\r\n"
        case .cr: return "\r"
        }
    }

    public var displayName: String {
        switch self {
        case .lf: return "LF (Unix)"
        case .crlf: return "CRLF (Windows)"
        case .cr: return "CR (Classic Mac)"
        }
    }

    /// Short status label matching the existing status-bar text.
    public var shortLabel: String {
        switch self {
        case .lf: return "LF"
        case .crlf: return "CRLF"
        case .cr: return "CR"
        }
    }
}

public enum ForkLineEndingConverter {

    /// Detect the dominant line ending. Mirrors the status-bar heuristic: CRLF wins if present,
    /// then bare CR, else LF (the default for content with no line breaks).
    public static func detect(_ text: String) -> ForkLineEnding {
        if text.contains("\r\n") { return .crlf }
        if text.contains("\r") { return .cr }
        return .lf
    }

    /// Normalize all line endings in `text` to `target`. Idempotent; safe on mixed input.
    public static func convert(_ text: String, to target: ForkLineEnding) -> String {
        // First normalize everything to LF (handling CRLF before bare CR), then expand to target.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard target != .lf else { return normalized }
        return normalized.replacingOccurrences(of: "\n", with: target.literal)
    }
}
