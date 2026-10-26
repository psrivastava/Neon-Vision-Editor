//
//  DocumentFormatter.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Hand-rolled XML/HTML pretty-print + minify, ported in spirit from NotepadMac's DocumentFormatter.
//  Foundation-only, no external dependency. JSON formatting stays on NVE's existing path
//  (ContentView+Actions.transformCurrentJSONDocument); this covers the XML/HTML gap only.
//
//  Pure and `Sendable` so it is test-target-safe and never touches upstream code.
//

import Foundation

public enum ForkDocumentFormatter {

    public enum FormatError: Error, Equatable, Sendable {
        case unbalancedTags
        case empty
    }

    /// Languages this formatter handles. JSON intentionally excluded (handled elsewhere).
    public static func handles(language: String) -> Bool {
        let lang = language.lowercased()
        return lang == "xml" || lang == "html" || lang == "xhtml" || lang == "svg"
    }

    /// Void/self-closing HTML elements that never get a separate closing tag.
    private static let voidElements: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    // MARK: - Public API

    /// Pretty-print XML/HTML with two-space indentation.
    /// Returns the reindented markup; throws `.empty` for blank input.
    public static func prettyPrint(_ input: String, indent: String = "  ") throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FormatError.empty }

        let tokens = tokenize(trimmed)
        var out: [String] = []
        var depth = 0

        for token in tokens {
            switch token {
            case .text(let value):
                let collapsed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !collapsed.isEmpty else { continue }
                out.append(String(repeating: indent, count: depth) + collapsed)
            case .tag(let raw, let kind, _):
                switch kind {
                case .close:
                    depth = max(0, depth - 1)
                    out.append(String(repeating: indent, count: depth) + raw)
                case .open:
                    out.append(String(repeating: indent, count: depth) + raw)
                    depth += 1
                case .selfContained:
                    out.append(String(repeating: indent, count: depth) + raw)
                }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// Minify XML/HTML: strip inter-tag whitespace and collapse runs of spaces in text nodes.
    public static func minify(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw FormatError.empty }

        let tokens = tokenize(trimmed)
        var out = ""
        for token in tokens {
            switch token {
            case .tag(let raw, _, _):
                out += raw
            case .text(let value):
                let collapsed = value
                    .replacingOccurrences(of: "\n", with: " ")
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                if !collapsed.isEmpty { out += collapsed }
            }
        }
        return out
    }

    // MARK: - Tokenizer

    private enum TagKind { case open, close, selfContained }

    private enum Token {
        case tag(raw: String, kind: TagKind, name: String)
        case text(String)
    }

    /// Split markup into tag and text tokens. Comments, declarations, CDATA, and processing
    /// instructions are treated as self-contained tags so they are never indented as containers.
    private static func tokenize(_ input: String) -> [Token] {
        var tokens: [Token] = []
        var chars = Array(input)
        var i = 0
        var textBuffer = ""

        func flushText() {
            if !textBuffer.isEmpty { tokens.append(.text(textBuffer)); textBuffer = "" }
        }

        while i < chars.count {
            if chars[i] == "<" {
                flushText()
                // Find the matching '>' (naive; adequate for well-formed editor content).
                var j = i + 1
                while j < chars.count && chars[j] != ">" { j += 1 }
                let hasClose = j < chars.count
                let raw = String(chars[i...(hasClose ? j : chars.count - 1)])
                tokens.append(classifyTag(raw))
                i = hasClose ? j + 1 : chars.count
            } else {
                textBuffer.append(chars[i])
                i += 1
            }
        }
        flushText()
        return tokens
    }

    private static func classifyTag(_ raw: String) -> Token {
        // Non-element constructs are always self-contained.
        if raw.hasPrefix("<!--") || raw.hasPrefix("<!") || raw.hasPrefix("<?") {
            return .tag(raw: raw, kind: .selfContained, name: "")
        }
        let inner = raw.dropFirst().dropLast() // strip < >
        let isClose = inner.hasPrefix("/")
        let isSelfClosing = inner.hasSuffix("/")
        let name = elementName(from: inner)

        if isClose {
            return .tag(raw: raw, kind: .close, name: name)
        }
        if isSelfClosing || voidElements.contains(name.lowercased()) {
            return .tag(raw: raw, kind: .selfContained, name: name)
        }
        return .tag(raw: raw, kind: .open, name: name)
    }

    private static func elementName(from inner: Substring) -> String {
        var body = inner
        if body.hasPrefix("/") { body = body.dropFirst() }
        var name = ""
        for ch in body {
            if ch.isWhitespace || ch == ">" || ch == "/" { break }
            name.append(ch)
        }
        return name
    }
}
