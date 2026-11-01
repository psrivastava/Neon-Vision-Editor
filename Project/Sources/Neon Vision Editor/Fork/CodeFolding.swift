//
//  CodeFolding.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Code folding, phase 1: the structural model. A `ForkFoldRange` is a foldable region derived
//  from the tree-sitter parse tree (every named node that spans more than one line), tagged with
//  its nesting `depth`. The actual range computation lives in `TreeSitterHighlighter.swift` next
//  to the (private) per-language engine it reuses — see `forkTreeSitterFoldRanges(language:text:)`.
//
//  Folding is tree-sitter-only by design: with the regex engine there is no structural tree, so
//  `forkCurrentSyntaxEngine() == .treeSitter` gates the whole feature (mirrors the highlighter seam).
//
//  Rendering the fold inside the virtual editor (hiding line ranges + gutter chevrons) is a later
//  phase; this file deliberately contains no view code so it compiles and unit-tests in isolation.
//

import Foundation

/// A foldable region of a document, in 0-based logical line coordinates.
///
/// `headerLine` stays visible when folded; `headerLine + 1 ... endLine` is what a renderer would
/// hide. `depth` is 1-based: the outermost foldable block is depth 1, a block nested inside it is
/// depth 2, and so on. "Fold Level N" folds every region whose `depth >= N` (so level 1 collapses
/// everything, level 9 collapses only the deepest blocks).
public nonisolated struct ForkFoldRange: Equatable, Sendable {
    /// 0-based line that carries the fold (remains visible when collapsed).
    public let headerLine: Int
    /// 0-based last line of the region (inclusive).
    public let endLine: Int
    /// 1-based nesting depth (outermost foldable block == 1).
    public let depth: Int

    public init(headerLine: Int, endLine: Int, depth: Int) {
        self.headerLine = headerLine
        self.endLine = endLine
        self.depth = depth
    }

    /// Number of lines hidden when this region is collapsed (the header stays, the body hides).
    public var hiddenLineCount: Int { max(0, endLine - headerLine) }

    /// A region is only worth folding if it hides at least one line.
    public var isFoldable: Bool { endLine > headerLine }
}

public nonisolated enum ForkCodeFolding {
    /// The depth range the "Fold/Unfold Level N" commands expose.
    public static let levelRange: ClosedRange<Int> = 1...9

    /// Collapse the set of raw fold ranges to at most one per header line, keeping the widest
    /// (outermost) region for each header and dropping non-foldable single-line regions. Sorted by
    /// header line. Rendering and the fold model both want this normalized form.
    public static func normalize(_ ranges: [ForkFoldRange]) -> [ForkFoldRange] {
        var widestByHeader: [Int: ForkFoldRange] = [:]
        for range in ranges where range.isFoldable {
            if let existing = widestByHeader[range.headerLine] {
                // Keep the region that hides more lines; on a tie keep the shallower depth.
                if range.endLine > existing.endLine ||
                    (range.endLine == existing.endLine && range.depth < existing.depth) {
                    widestByHeader[range.headerLine] = range
                }
            } else {
                widestByHeader[range.headerLine] = range
            }
        }
        return widestByHeader.values.sorted { $0.headerLine < $1.headerLine }
    }
}
