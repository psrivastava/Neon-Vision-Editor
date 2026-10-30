//
//  FormatRouter.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Single entry point behind the unified "Format Document" command. Routes by the document's
//  language to whichever formatter understands that grammar:
//
//    JSON          → JSONPreviewDocument.formattedText  (upstream, streaming byte formatter)
//    XML/HTML/SVG  → ForkDocumentFormatter              (fork, tag-aware pretty/minify)
//    C-family      → ForkCodeReindenter                 (fork, bracket-depth re-indent)
//
//  Keeping the routing here means the command layer never grows a language switch, and adding a
//  language later is one line in `kind(for:)`.
//

import Foundation

/// Main-actor isolated (project default): it calls `ForkDocumentFormatter`, which is too.
enum ForkFormatRouter {

    enum Kind: Equatable {
        case json
        case markup
        case braces
        case unsupported
    }

    enum RouterError: Error, Equatable, Sendable {
        /// The language has no formatter; carries a user-facing reason.
        case unsupported(language: String)
        /// Minify was requested for a language where it has no meaning (code, not markup).
        case minifyUnsupported
    }

    static func kind(for language: String) -> Kind {
        let lang = language.lowercased().trimmingCharacters(in: .whitespaces)
        if lang.hasPrefix("json") { return .json }
        if ForkDocumentFormatter.handles(language: lang) { return .markup }
        if ForkCodeReindenter.handles(language: lang) { return .braces }
        return .unsupported
    }

    /// True when "Minify" is meaningful for this language (markup and JSON only).
    static func supportsMinify(language: String) -> Bool {
        switch kind(for: language) {
        case .json, .markup: return true
        case .braces, .unsupported: return false
        }
    }

    /// Format `source` for `language`. `indentUnit` is one indent level from the editor's settings,
    /// used only by the brace re-indenter — JSON and markup keep their formatters' own conventions.
    static func format(
        _ source: String,
        language: String,
        indentUnit: String
    ) throws -> String {
        switch kind(for: language) {
        case .json:
            var output = try JSONPreviewDocument.formattedText(source, prettyPrinted: true)
            if !output.hasSuffix("\n") { output.append("\n") }
            return output
        case .markup:
            return try ForkDocumentFormatter.prettyPrint(source)
        case .braces:
            return ForkCodeReindenter.reindent(source, indentUnit: indentUnit)
        case .unsupported:
            throw RouterError.unsupported(language: language)
        }
    }

    /// Minify `source`. Only JSON and markup support this.
    static func minify(_ source: String, language: String) throws -> String {
        switch kind(for: language) {
        case .json:
            return try JSONPreviewDocument.formattedText(source, prettyPrinted: false)
        case .markup:
            return try ForkDocumentFormatter.minify(source)
        case .braces:
            throw RouterError.minifyUnsupported
        case .unsupported:
            throw RouterError.unsupported(language: language)
        }
    }

    /// Human-readable list for status messages when a language has no formatter.
    static let supportedSummary = "JSON, XML, HTML, SVG, and C-family code (Java, JS/TS, Swift, Kotlin, C/C++, C#, CSS)"
}
