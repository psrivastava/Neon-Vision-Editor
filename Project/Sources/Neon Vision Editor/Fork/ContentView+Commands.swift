//
//  ContentView+Commands.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Editor-side handlers for fork commands. Lives in a fork file so upstream merges stay clean.
//
//  v2.1 NOTE: the macOS editor is now a virtual editor (no NSTextView/NSTextStorage), so the
//  transform/copy handlers operate on `currentContentBinding` — mirroring upstream's own
//  `transformCurrentJSONDocument` (ContentView+Actions). This is whole-document scope; selection-
//  scoped transforms are a later enhancement (would read `currentSelectionSnapshotRange` and splice).
//
//  Observers are attached in ContentView.body via a `// MARK: - FORK command observers` hook
//  (5 `.onReceive` modifiers), each gated by `forkMatchesWindow(_:)`.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

extension ContentView {

    // MARK: - Window routing

    /// Fork mirror of the upstream per-window filter. On iOS there is a single window, so always true.
    func forkMatchesWindow(_ notif: Notification) -> Bool {
#if os(macOS)
        guard let target = notif.userInfo?[EditorCommandUserInfo.windowNumber] as? Int else { return true }
        return target == hostWindowNumber
#else
        return true
#endif
    }

    // MARK: - String transforms

    /// Apply a transform to the whole document via the content binding (virtual-editor safe).
    func forkApplyStringTransform(_ transform: ForkStringTransform) {
        guard !requiresMaterializedEditorTransform() else { return }
        let source = currentContentBinding.wrappedValue
        let result = transform.apply(to: source)
        guard result != source else {
            forkStatusMessage = "\(transform.title): no change"
            return
        }
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = result
        forkStatusMessage = "Applied \(transform.title)"
    }

    // MARK: - Document formatting

    /// Ceiling for formatting a file-backed (virtual) document. Formatting is inherently
    /// whole-document, so the text has to be materialized; above this size that costs more memory
    /// than the feature is worth, and we say so instead of hanging or silently doing nothing.
    private static let forkFormatMaxUTF16Length = 10_000_000

    /// Unified "Format Document" entry point. Routes by language (JSON / markup / C-family code)
    /// and works for both in-memory and file-backed documents.
    func forkFormatDocument(pretty: Bool) {
        let language = currentLanguage
        guard ForkFormatRouter.kind(for: language) != .unsupported else {
            forkStatusMessage = "No formatter for \(language). Supported: \(ForkFormatRouter.supportedSummary)."
            return
        }
        if !pretty, !ForkFormatRouter.supportsMinify(language: language) {
            forkStatusMessage = "Minify applies to JSON and markup documents only."
            return
        }

        guard let source = forkFormattableSourceText() else { return }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let indentUnit = indentStyle == "tabs" ? "\t" : String(repeating: " ", count: max(1, indentWidth))
        let output: String
        do {
            output = pretty
                ? try ForkFormatRouter.format(source, language: language, indentUnit: indentUnit)
                : try ForkFormatRouter.minify(source, language: language)
        } catch ForkDocumentFormatter.FormatError.empty {
            return
        } catch let error as ForkFormatRouter.RouterError {
            forkStatusMessage = error == .minifyUnsupported
                ? "Minify applies to JSON and markup documents only."
                : "No formatter for \(language)."
            return
        } catch {
            forkStatusMessage = ForkFormatRouter.kind(for: language) == .json
                ? "Invalid JSON: \(error.localizedDescription)"
                : "Could not format this document."
            return
        }

        guard output != source else {
            forkStatusMessage = "Already formatted"
            return
        }
        guard forkWriteFormattedText(output) else { return }
        forkStatusMessage = pretty ? "Formatted document" : "Minified document"
    }

    /// Back-compat shim: the markup-specific menu items and notifications still route here.
    func forkFormatMarkup(pretty: Bool) {
        forkFormatDocument(pretty: pretty)
    }

    /// Whole-document text for formatting, materializing a file-backed document when needed.
    /// Returns nil (after setting a status message) when the document cannot be formatted.
    private func forkFormattableSourceText() -> String? {
        guard let tab = viewModel.selectedTab else { return nil }
        guard tab.usesFileBackedStorage else {
            return currentContentBinding.wrappedValue
        }
        if tab.isPartialFilePreview {
            forkStatusMessage = "This file is open as a partial preview; formatting needs the whole document."
            return nil
        }
        let length = tab.document.utf16Length
        guard length <= Self.forkFormatMaxUTF16Length else {
            forkStatusMessage = "Document is too large to format (over \(Self.forkFormatMaxUTF16Length / 1_000_000) M characters)."
            return nil
        }
        let text = tab.document.string()
        guard !text.isEmpty || length == 0 else {
            forkStatusMessage = "Could not read the document text."
            return nil
        }
        return text
    }

    /// Write formatted text back through whichever storage the tab uses.
    private func forkWriteFormattedText(_ output: String) -> Bool {
        guard let tab = viewModel.selectedTab else { return false }
        if tab.usesFileBackedStorage {
            guard tab.replaceContentStorage(with: output, markDirty: true) else {
                forkStatusMessage = "Could not apply the formatted text."
                return false
            }
            editorExternalMutationRevision &+= 1
            return true
        }
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = output
        return true
    }

    // MARK: - Line-ending conversion

    func forkConvertLineEndings(to target: ForkLineEnding) {
        let source = currentContentBinding.wrappedValue
        let converted = ForkLineEndingConverter.convert(source, to: target)
        guard converted != source else {
            forkStatusMessage = "Line endings already \(target.shortLabel)"
            return
        }
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = converted
        forkStatusMessage = "Converted line endings to \(target.shortLabel)"
    }

    // MARK: - Copy (plain-text; virtual editor has no attributed storage to export)

    /// v2.1: the virtual editor exposes no NSTextStorage, so rich HTML/RTF export isn't available.
    /// Degrade to copying the document text as plain string. Rich export can return if the editor
    /// later exposes an attributed snapshot.
    func forkCopyAsRichText() {
        let text = currentContentBinding.wrappedValue
        guard !text.isEmpty else { return }
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
#endif
        forkStatusMessage = "Copied document text"
    }

    // MARK: - Breadcrumb bar

    @ViewBuilder
    var forkBreadcrumbBar: some View {
        if UserDefaults.standard.bool(forKey: "SettingsForkShowBreadcrumbBar"),
           !viewModel.isBrainDumpMode {
            ForkBreadcrumbBar(
                fileURL: viewModel.selectedTab?.fileURL,
                language: currentLanguage
            )
        }
    }
}

// MARK: - FORK command observers (single modifier)

/// Bundles the 5 fork command `.onReceive` observers into one `ViewModifier`. Applying one
/// modifier instead of five chained `.onReceive` keeps `ContentView.body` from tripping the
/// SwiftUI type-checker timeout. Handlers are passed in as closures (resolved here, not in body).
struct ForkCommandObservers: ViewModifier {
    let matchesWindow: (Notification) -> Bool
    let applyTransform: (ForkStringTransform) -> Void
    let formatMarkup: (Bool) -> Void
    let convertLineEndings: (ForkLineEnding) -> Void
    let copyRichText: () -> Void
    /// The raw `SettingsSyntaxEngine` value from ContentView; observing it here (not in
    /// ContentView.body) keeps the already-huge body from tripping the type-checker.
    let syntaxEngineRaw: String
    /// Called when the engine toggles, so ContentView can bump its highlight refresh token.
    let onSyntaxEngineChange: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: syntaxEngineRaw) { _, _ in onSyntaxEngineChange() }
            .onReceive(NotificationCenter.default.publisher(for: .forkApplyStringTransformRequested)) { notif in
                guard matchesWindow(notif),
                      let raw = notif.object as? String,
                      let transform = ForkStringTransform(rawValue: raw) else { return }
                applyTransform(transform)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkFormatMarkupRequested)) { notif in
                guard matchesWindow(notif) else { return }
                formatMarkup(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkMinifyMarkupRequested)) { notif in
                guard matchesWindow(notif) else { return }
                formatMarkup(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkFormatDocumentRequested)) { notif in
                guard matchesWindow(notif) else { return }
                formatMarkup(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkMinifyDocumentRequested)) { notif in
                guard matchesWindow(notif) else { return }
                formatMarkup(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkConvertLineEndingsRequested)) { notif in
                guard matchesWindow(notif),
                      let raw = notif.object as? String,
                      let target = ForkLineEnding(rawValue: raw) else { return }
                convertLineEndings(target)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkCopyAsRichTextRequested)) { notif in
                guard matchesWindow(notif) else { return }
                copyRichText()
            }
    }
}
