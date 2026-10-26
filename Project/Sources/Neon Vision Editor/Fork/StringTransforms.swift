//
//  StringTransforms.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Pure, platform-neutral string transforms ported from NotepadMac's transform suite.
//  Kept dependency-free and Sendable so it is test-target-safe and never touches upstream code.
//  Wiring into menus/editor lives in ForkStringTransformsCommands.swift (macOS/iOS).
//

import Foundation

/// A single text transform that maps an input string to an output string.
///
/// Every case is a pure function of its input, so the whole enum is `Sendable` and unit-testable
/// without any editor or UI context. Applied either to the current selection or the whole document.
public enum ForkStringTransform: String, CaseIterable, Sendable {
    // Case
    case upperCase
    case lowerCase
    case titleCase
    case toggleCase
    case camelCase
    case snakeCase
    case kebabCase

    // Encoding / escaping
    case urlEncode
    case urlDecode
    case base64Encode
    case base64Decode
    case htmlEncode
    case htmlDecode

    // Lines / whitespace
    case sortLinesAscending
    case sortLinesDescending
    case deduplicateLines
    case reverseLines
    case trimTrailingWhitespace

    // Numbers
    case decimalToHex
    case hexToDecimal

    /// Human-readable menu title.
    public var title: String {
        switch self {
        case .upperCase: return "UPPERCASE"
        case .lowerCase: return "lowercase"
        case .titleCase: return "Title Case"
        case .toggleCase: return "Toggle Case"
        case .camelCase: return "camelCase"
        case .snakeCase: return "snake_case"
        case .kebabCase: return "kebab-case"
        case .urlEncode: return "URL Encode"
        case .urlDecode: return "URL Decode"
        case .base64Encode: return "Base64 Encode"
        case .base64Decode: return "Base64 Decode"
        case .htmlEncode: return "HTML Encode"
        case .htmlDecode: return "HTML Decode"
        case .sortLinesAscending: return "Sort Lines (A→Z)"
        case .sortLinesDescending: return "Sort Lines (Z→A)"
        case .deduplicateLines: return "Remove Duplicate Lines"
        case .reverseLines: return "Reverse Lines"
        case .trimTrailingWhitespace: return "Trim Trailing Whitespace"
        case .decimalToHex: return "Decimal → Hex"
        case .hexToDecimal: return "Hex → Decimal"
        }
    }

    /// Logical grouping for building submenus.
    public enum Group: String, CaseIterable, Sendable {
        case caseConversion = "Case"
        case encoding = "Encoding & Escaping"
        case lines = "Lines & Whitespace"
        case numbers = "Numbers"
    }

    public var group: Group {
        switch self {
        case .upperCase, .lowerCase, .titleCase, .toggleCase, .camelCase, .snakeCase, .kebabCase:
            return .caseConversion
        case .urlEncode, .urlDecode, .base64Encode, .base64Decode, .htmlEncode, .htmlDecode:
            return .encoding
        case .sortLinesAscending, .sortLinesDescending, .deduplicateLines, .reverseLines, .trimTrailingWhitespace:
            return .lines
        case .decimalToHex, .hexToDecimal:
            return .numbers
        }
    }

    /// Apply the transform. Returns the transformed string, or the original input unchanged when the
    /// transform cannot apply (e.g. undecodable Base64) so a no-op never destroys the user's text.
    public func apply(to input: String) -> String {
        switch self {
        case .upperCase: return input.uppercased()
        case .lowerCase: return input.lowercased()
        case .titleCase: return input.capitalized
        case .toggleCase: return Self.toggleCase(input)
        case .camelCase: return Self.recase(input, style: .camel)
        case .snakeCase: return Self.recase(input, style: .snake)
        case .kebabCase: return Self.recase(input, style: .kebab)
        case .urlEncode:
            return input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? input
        case .urlDecode:
            return input.removingPercentEncoding ?? input
        case .base64Encode:
            return Data(input.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let decoded = String(data: data, encoding: .utf8) else { return input }
            return decoded
        case .htmlEncode: return Self.htmlEncode(input)
        case .htmlDecode: return Self.htmlDecode(input)
        case .sortLinesAscending: return Self.sortLines(input, ascending: true)
        case .sortLinesDescending: return Self.sortLines(input, ascending: false)
        case .deduplicateLines: return Self.deduplicateLines(input)
        case .reverseLines: return Self.reverseLines(input)
        case .trimTrailingWhitespace: return Self.trimTrailingWhitespace(input)
        case .decimalToHex: return Self.decimalToHex(input)
        case .hexToDecimal: return Self.hexToDecimal(input)
        }
    }

    // MARK: - Case helpers

    private static func toggleCase(_ input: String) -> String {
        String(input.map { ch in
            if ch.isUppercase { return Character(ch.lowercased()) }
            if ch.isLowercase { return Character(ch.uppercased()) }
            return ch
        })
    }

    private enum RecaseStyle { case camel, snake, kebab }

    /// Split into words on non-alphanumeric boundaries and camelCase humps, then re-join per style.
    private static func recase(_ input: String, style: RecaseStyle) -> String {
        let words = splitWords(input)
        guard !words.isEmpty else { return input }
        switch style {
        case .snake: return words.map { $0.lowercased() }.joined(separator: "_")
        case .kebab: return words.map { $0.lowercased() }.joined(separator: "-")
        case .camel:
            let lowered = words.map { $0.lowercased() }
            let head = lowered[0]
            let tail = lowered.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return ([head] + tail).joined()
        }
    }

    /// Break an identifier-ish string into words on separators and camelCase humps.
    private static func splitWords(_ input: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for ch in input {
            let isSeparator = !ch.isLetter && !ch.isNumber
            if isSeparator {
                if !current.isEmpty { words.append(current); current = "" }
                previous = nil
                continue
            }
            // camelCase hump: lower/digit followed by upper starts a new word.
            if let prev = previous, prev.isLowercase || prev.isNumber, ch.isUppercase {
                if !current.isEmpty { words.append(current); current = "" }
            }
            current.append(ch)
            previous = ch
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    // MARK: - HTML helpers

    private static func htmlEncode(_ input: String) -> String {
        var out = ""
        out.reserveCapacity(input.count)
        for ch in input {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    private static func htmlDecode(_ input: String) -> String {
        var out = input
        // Order matters: decode &amp; last so "&amp;lt;" round-trips correctly.
        let named: [(String, String)] = [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""),
            ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")
        ]
        for (entity, char) in named {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        return out
    }

    // MARK: - Line helpers

    /// Split preserving nothing about the trailing newline; callers operate on logical lines.
    private static func lines(_ input: String) -> [String] {
        input.components(separatedBy: "\n")
    }

    private static func sortLines(_ input: String, ascending: Bool) -> String {
        let sorted = lines(input).sorted { a, b in
            let result = a.localizedCaseInsensitiveCompare(b)
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
        return sorted.joined(separator: "\n")
    }

    private static func deduplicateLines(_ input: String) -> String {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines(input) where seen.insert(line).inserted {
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    private static func reverseLines(_ input: String) -> String {
        lines(input).reversed().joined(separator: "\n")
    }

    private static func trimTrailingWhitespace(_ input: String) -> String {
        lines(input)
            .map { line -> String in
                var view = Substring(line)
                while let last = view.last, last == " " || last == "\t" {
                    view = view.dropLast()
                }
                return String(view)
            }
            .joined(separator: "\n")
    }

    // MARK: - Number helpers

    /// Convert each whitespace-separated decimal token to 0x-prefixed hex; leaves non-numbers alone.
    private static func decimalToHex(_ input: String) -> String {
        mapTokens(input) { token in
            guard let value = Int(token) else { return token }
            let sign = value < 0 ? "-" : ""
            return "\(sign)0x" + String(abs(value), radix: 16)
        }
    }

    /// Convert each whitespace-separated hex token (0x-prefixed or bare) to decimal; leaves others alone.
    private static func hexToDecimal(_ input: String) -> String {
        mapTokens(input) { token in
            var body = token
            var sign = ""
            if body.hasPrefix("-") { sign = "-"; body.removeFirst() }
            if body.lowercased().hasPrefix("0x") { body = String(body.dropFirst(2)) }
            guard !body.isEmpty, let value = Int(body, radix: 16) else { return token }
            return sign + String(value)
        }
    }

    /// Apply `transform` to each whitespace-delimited token while preserving the original spacing.
    private static func mapTokens(_ input: String, _ transform: (String) -> String) -> String {
        var result = ""
        var token = ""
        for ch in input {
            if ch.isWhitespace {
                if !token.isEmpty { result += transform(token); token = "" }
                result.append(ch)
            } else {
                token.append(ch)
            }
        }
        if !token.isEmpty { result += transform(token) }
        return result
    }
}
