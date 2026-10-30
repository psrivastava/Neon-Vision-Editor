//
//  CodeReindenter.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Brace-depth re-indenter for C-family languages (Java, JS/TS, Swift, Kotlin, C/C++, C#, CSS, …).
//
//  Scope note: this RE-INDENTS. It does not re-wrap long lines, reorder imports, or normalize
//  spacing inside expressions — that needs a real language parser per language (google-java-format
//  needs a JVM, clang-format is an external binary), neither of which can ship inside a sandboxed
//  Mac app. Re-indentation is the part that is both safe to do generically and the thing people
//  actually want after pasting code.
//
//  Safety rule: anything the scanner cannot reason about is emitted VERBATIM. Lines inside block
//  comments and multi-line string literals (Java text blocks, JS template literals, Swift/Python
//  triple quotes) keep the author's original text, because re-indenting them changes their value
//  or their rendered shape.
//
//  Pure (Foundation only) and never touches upstream code.
//

import Foundation

enum ForkCodeReindenter {

    /// Languages handled here. JSON and XML/HTML are deliberately absent — they have dedicated
    /// formatters (`JSONPreviewDocument` and `ForkDocumentFormatter`) that understand their grammar.
    /// Rust is absent on purpose: its lifetimes (`'a`) look like unterminated char literals to this
    /// scanner and would swallow brackets.
    private static let supportedLanguages: Set<String> = [
        "java", "javascript", "js", "jsx", "typescript", "ts", "tsx",
        "swift", "kotlin", "kt", "c", "c++", "cpp", "objective-c", "objc",
        "c#", "csharp", "cs", "go", "php", "dart",
        "groovy", "scala", "css", "scss", "less"
    ]

    static func handles(language: String) -> Bool {
        supportedLanguages.contains(normalized(language))
    }

    private static func normalized(_ language: String) -> String {
        language.lowercased().trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Public API

    /// Re-indent `source` by bracket depth. `indentUnit` is one level of indentation
    /// (e.g. `"    "` or `"\t"`), matching the editor's own indent settings.
    static func reindent(_ source: String, indentUnit: String) -> String {
        // Preserve the document's line terminator rather than forcing LF.
        let terminator = detectTerminator(in: source)
        let lines = source.components(separatedBy: .newlines)

        var scanner = ScanState()
        var output: [String] = []
        output.reserveCapacity(lines.count)

        for line in lines {
            // Inside a block comment or multi-line string, the author's text is the content.
            if scanner.isInVerbatimRegion {
                output.append(line)
                scanner.consumeVerbatim(line)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                output.append("")
                scanner.consume(trimmed)
                continue
            }

            let analysis = scanner.consume(trimmed)
            let depth = max(0, scanner.depthBeforeLine - analysis.leadingClosers)
            output.append(String(repeating: indentUnit, count: depth) + trimmed)
        }

        return output.joined(separator: terminator)
    }

    private static func detectTerminator(in source: String) -> String {
        if source.contains("\r\n") { return "\r\n" }
        if source.contains("\r") && !source.contains("\n") { return "\r" }
        return "\n"
    }

    // MARK: - Scanner

    private struct LineAnalysis {
        /// Closing brackets at the very start of the line; these dedent the line itself.
        var leadingClosers = 0
    }

    /// Tracks bracket depth and which multi-line construct (if any) we are currently inside.
    private struct ScanState {
        private enum Verbatim {
            case blockComment
            case backtickString          // JS/TS template literal
            case tripleQuoteString       // Java text block, Swift/Kotlin/Python triple quotes
        }

        private var depth = 0
        private var verbatim: Verbatim?

        /// Depth that applies to the line currently being emitted, captured before its own
        /// opens/closes are applied.
        private(set) var depthBeforeLine = 0

        var isInVerbatimRegion: Bool { verbatim != nil }

        /// Advance past a line that is emitted verbatim, looking only for its terminator.
        /// Whatever follows the terminator on the same line is ordinary code again and must be
        /// scanned, or a closer like the `)` in Java's `""");` would be lost.
        mutating func consumeVerbatim(_ line: String) {
            let chars = Array(line)
            var i = 0
            while i < chars.count {
                var terminatorEnd: Int?
                switch verbatim {
                case .blockComment:
                    if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" { terminatorEnd = i + 2 }
                case .backtickString:
                    if chars[i] == "\\" { i += 2; continue }
                    if chars[i] == "`" { terminatorEnd = i + 1 }
                case .tripleQuoteString:
                    if chars[i] == "\\" { i += 2; continue }
                    if isTripleQuote(chars, at: i) { terminatorEnd = i + 3 }
                case nil:
                    return
                }
                if let end = terminatorEnd {
                    verbatim = nil
                    let rest = String(chars[min(end, chars.count)...])
                    // The verbatim line keeps its own indent, but its closers still change the
                    // depth seen by the lines after it.
                    consume(rest.trimmingCharacters(in: .whitespaces))
                    return
                }
                i += 1
            }
        }

        /// Scan one code line: update bracket depth and report its leading closers.
        @discardableResult
        mutating func consume(_ line: String) -> LineAnalysis {
            depthBeforeLine = depth
            var analysis = LineAnalysis()
            var sawContent = false

            let chars = Array(line)
            var i = 0
            var delta = 0

            while i < chars.count {
                let ch = chars[i]

                // String and comment openers.
                if ch == "/", i + 1 < chars.count {
                    if chars[i + 1] == "/" { break }                       // line comment: ignore rest
                    if chars[i + 1] == "*" {
                        if let end = findBlockCommentEnd(chars, from: i + 2) {
                            i = end
                            continue
                        }
                        verbatim = .blockComment
                        break
                    }
                }
                if isTripleQuote(chars, at: i) {
                    if let end = findTripleQuoteEnd(chars, from: i + 3) {
                        i = end
                        sawContent = true
                        continue
                    }
                    verbatim = .tripleQuoteString
                    break
                }
                if ch == "`" {
                    if let end = findSimpleStringEnd(chars, from: i + 1, quote: "`") {
                        i = end
                        sawContent = true
                        continue
                    }
                    verbatim = .backtickString
                    break
                }
                if ch == "\"" || ch == "'" {
                    sawContent = true
                    // An unterminated single/double quote is almost always a typo rather than a
                    // multi-line construct, so stop scanning this line instead of swallowing the file.
                    guard let end = findSimpleStringEnd(chars, from: i + 1, quote: ch) else { break }
                    i = end
                    continue
                }

                switch ch {
                case "{", "(", "[":
                    delta += 1
                    sawContent = true
                case "}", ")", "]":
                    delta -= 1
                    if !sawContent { analysis.leadingClosers += 1 }
                    sawContent = true
                default:
                    if !ch.isWhitespace { sawContent = true }
                }
                i += 1
            }

            depth = max(0, depth + delta)
            return analysis
        }

        // MARK: Character helpers

        private func isTripleQuote(_ chars: [Character], at index: Int) -> Bool {
            guard index + 2 < chars.count else { return false }
            return chars[index] == "\"" && chars[index + 1] == "\"" && chars[index + 2] == "\""
        }

        /// Index just past the closing quote, or nil when the literal runs past this line.
        private func findSimpleStringEnd(_ chars: [Character], from start: Int, quote: Character) -> Int? {
            var i = start
            while i < chars.count {
                if chars[i] == "\\" { i += 2; continue }
                if chars[i] == quote { return i + 1 }
                i += 1
            }
            return nil
        }

        private func findTripleQuoteEnd(_ chars: [Character], from start: Int) -> Int? {
            var i = start
            while i < chars.count {
                if chars[i] == "\\" { i += 2; continue }
                if isTripleQuote(chars, at: i) { return i + 3 }
                i += 1
            }
            return nil
        }

        private func findBlockCommentEnd(_ chars: [Character], from start: Int) -> Int? {
            var i = start
            while i < chars.count {
                if chars[i] == "*", i + 1 < chars.count, chars[i + 1] == "/" { return i + 2 }
                i += 1
            }
            return nil
        }
    }
}
