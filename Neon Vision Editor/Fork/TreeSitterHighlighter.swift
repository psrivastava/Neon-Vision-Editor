//
//  TreeSitterHighlighter.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Tree-sitter-backed syntax coloring, consumed at the `fastSyntaxColorRanges` seam. Returns the
//  same `[(NSRange, Color)]` shape the regex pipeline produces, with capture names mapped to the
//  active theme's `SyntaxColors`, so it honors themes and slots into the existing viewport /
//  large-file gating unchanged.
//
//  Phase B: HTML is wired end-to-end. Any other language returns nil → the seam falls back to regex,
//  so selecting the tree-sitter engine only *upgrades* HTML and never breaks another language.
//
//  Concurrency: the seam (`fastSyntaxColorRanges`) is `nonisolated` and runs off the main actor.
//  tree-sitter's `Parser`/`Query` objects are NOT thread-safe, so the per-language engine is confined
//  behind an `NVELock` (the same pattern `SyntaxRegexCache` uses) — this keeps the seam synchronous
//  while serializing parser access. Parses are viewport-scoped (the caller passes the visible range),
//  cheap enough to run inline.
//

import SwiftUI
import Foundation

#if canImport(SwiftTreeSitter) && canImport(TreeSitterHTML)
import SwiftTreeSitter
import TreeSitterHTML
import TreeSitterCSS
import TreeSitterJSON
import TreeSitterJavaScript
import TreeSitterPython
import TreeSitterC
import TreeSitterBash
import TreeSitterGo
import TreeSitterRuby
import TreeSitterRust
import TreeSitterJava

/// One lazily-built, lock-guarded tree-sitter engine per language. Holds the compiled highlight query
/// (expensive to build) and a reusable parser. `@unchecked Sendable` via the NVELock confinement.
nonisolated private final class ForkTreeSitterEngine: @unchecked Sendable {
    let parser: Parser
    let query: Query

    init?(language: Language, highlightQuery: Query?) {
        guard let highlightQuery else { return nil }
        let parser = Parser()
        do {
            try parser.setLanguage(language)
        } catch {
            return nil
        }
        self.parser = parser
        self.query = highlightQuery
    }
}

/// Per-language engine cache. Building the `LanguageConfiguration` (which compiles the bundled
/// `highlights.scm`) is done once per language and cached.
nonisolated(unsafe) private let forkTreeSitterEngineCache = NVELock<[String: ForkTreeSitterEngine?]>([:])

nonisolated private func forkTreeSitterEngine(for language: String) -> ForkTreeSitterEngine? {
    // Return the cached engine (including a cached nil for "grammar not available") if present.
    if let cached = forkTreeSitterEngineCache.withLock({ $0[language] }) {
        return cached
    }

    // Map NVE's language identifiers (some are aliases, e.g. js/ts, py) onto a tree-sitter grammar's
    // C entry point + its SPM bundle name. `LanguageConfiguration(lang, name:)` auto-loads that
    // grammar's bundled highlights.scm from the "TreeSitter<Name>_TreeSitter<Name>" resource bundle.
    // Languages without a loaded grammar (cobol, vim, nginx, kotlin, latex, …) return nil → regex.
    let spec: (grammar: OpaquePointer, name: String)? = {
        switch language {
        case "html", "xml": return (tree_sitter_html(), "HTML") // XML approximated by the HTML grammar
        case "css": return (tree_sitter_css(), "CSS")
        case "json", "jsonc", "json5", "ipynb": return (tree_sitter_json(), "JSON")
        case "javascript", "js", "typescript", "ts": return (tree_sitter_javascript(), "JavaScript") // TS approximated by JS
        case "python", "py": return (tree_sitter_python(), "Python")
        case "c", "cpp", "c++": return (tree_sitter_c(), "C")
        case "bash", "sh", "zsh", "shell": return (tree_sitter_bash(), "Bash")
        case "go": return (tree_sitter_go(), "Go")
        case "ruby", "rb": return (tree_sitter_ruby(), "Ruby")
        case "rust", "rs": return (tree_sitter_rust(), "Rust")
        case "java": return (tree_sitter_java(), "Java")
        default: return nil
        }
    }()

    let built: ForkTreeSitterEngine? = {
        guard let spec else { return nil }
        let lang = Language(spec.grammar)
        guard let config = try? LanguageConfiguration(lang, name: spec.name) else { return nil }
        return ForkTreeSitterEngine(language: lang, highlightQuery: config.queries[.highlights])
    }()

    forkTreeSitterEngineCache.withLock { $0[language] = built }
    return built
}

/// Map a tree-sitter highlight capture name (e.g. "tag", "attribute", "string.special") to a theme
/// `SyntaxColors` field. The most specific leading component wins; unknown captures return nil so the
/// base text color shows through (rather than mis-coloring).
nonisolated private func forkColor(forCapture capture: String, colors: SyntaxColors) -> Color? {
    let head = capture.split(separator: ".").first.map(String.init) ?? capture
    switch head {
    case "tag": return colors.tag
    case "attribute", "property": return colors.attribute
    case "string": return colors.string
    case "comment": return colors.comment
    case "number": return colors.number
    case "constant", "boolean": return colors.atom
    case "keyword": return colors.keyword
    case "type": return colors.type
    case "function", "method": return colors.def
    case "variable": return colors.variable
    case "operator", "punctuation": return nil // let punctuation stay base color; too noisy otherwise
    default: return nil
    }
}

nonisolated func forkTreeSitterColorRanges(
    language: String,
    text: NSString,
    in range: NSRange,
    colors: SyntaxColors
) -> [(NSRange, Color)]? {
    guard let engine = forkTreeSitterEngine(for: language) else { return nil }
    let fullString = text as String

    // Parse + query under the lock (parser/query are not thread-safe). Parse the whole document once;
    // the highlight query is then range-scoped to the requested (viewport) range so we only emit
    // colors the caller will use.
    return forkTreeSitterEngineCache.withLock { _ in
        guard let tree = engine.parser.parse(fullString),
              let root = tree.rootNode else { return nil }

        let cursor = engine.query.execute(node: root, in: tree)
        let rangeEnd = NSMaxRange(range)
        var out: [(NSRange, Color)] = []

        for match in cursor {
            for capture in match.captures {
                let r = capture.range // already UTF-16 (SwiftTreeSitter Node.range = byteRange/2 under UTF-16 parse)
                guard r.location != NSNotFound,
                      r.length > 0,
                      NSMaxRange(r) <= text.length,
                      r.location < rangeEnd,
                      NSMaxRange(r) > range.location, // overlaps the requested range
                      let name = capture.name,
                      let color = forkColor(forCapture: name, colors: colors) else { continue }
                out.append((r, color))
            }
        }
        return out.isEmpty ? nil : out
    }
}

#else

// Dependency not present in this build configuration — always fall back to regex.
nonisolated func forkTreeSitterColorRanges(
    language: String,
    text: NSString,
    in range: NSRange,
    colors: SyntaxColors
) -> [(NSRange, Color)]? {
    return nil
}

#endif
