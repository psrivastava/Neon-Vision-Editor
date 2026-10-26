//
//  Support.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Shared infrastructure for fork-only features ported from NotepadMac.
//  Centralizes the fork Notification.Name channel so upstream files need at most a one-line hook.
//
//  Isolation contract (see docs/Fork-Port-Tasks.md):
//    - All fork behavior lives in Neon Vision Editor/Fork/*.
//    - Upstream files are touched only via tiny `// MARK: - FORK` hooks.
//    - New cross-isolation types are Sendable; UI runs on @MainActor.
//

import Foundation

/// Notification channel for fork-added commands. Kept separate from upstream's catalog in
/// PanelsAndHelpers.swift so merges from upstream never collide with these names.
extension Notification.Name {
    /// Posted with `object: ForkStringTransform.rawValue` (String) to apply a transform.
    static let forkApplyStringTransformRequested = Notification.Name("forkApplyStringTransformRequested")
    /// Pretty-print the current XML/HTML document.
    static let forkFormatMarkupRequested = Notification.Name("forkFormatMarkupRequested")
    /// Minify the current XML/HTML document.
    static let forkMinifyMarkupRequested = Notification.Name("forkMinifyMarkupRequested")
    /// Copy the current selection (or whole document) as HTML + RTF to the pasteboard.
    static let forkCopyAsRichTextRequested = Notification.Name("forkCopyAsRichTextRequested")
    /// Convert the current document's line endings. Posted with `object: ForkLineEnding.rawValue`.
    static let forkConvertLineEndingsRequested = Notification.Name("forkConvertLineEndingsRequested")
    /// Show the fork command palette (Cmd+Shift+P).
    static let forkShowCommandPaletteRequested = Notification.Name("forkShowCommandPaletteRequested")
}

/// User-info keys for fork notifications. Mirrors upstream `EditorCommandUserInfo` windowNumber
/// so fork commands route to the correct window using the same filter (`matchesCurrentWindow`).
enum ForkCommandUserInfo {
    static let stringTransform = "forkStringTransform"
}
