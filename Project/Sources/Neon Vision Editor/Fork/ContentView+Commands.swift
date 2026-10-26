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
            findStatusMessage = "\(transform.title): no change"
            return
        }
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = result
        findStatusMessage = "Applied \(transform.title)"
    }

    // MARK: - Markup formatting

    func forkFormatMarkup(pretty: Bool) {
        guard ForkDocumentFormatter.handles(language: currentLanguage) else {
            findStatusMessage = "Formatting is available for XML, HTML, and SVG documents."
            return
        }
        guard !requiresMaterializedEditorTransform() else { return }
        let source = currentContentBinding.wrappedValue
        do {
            let output = pretty ? try ForkDocumentFormatter.prettyPrint(source)
                                : try ForkDocumentFormatter.minify(source)
            editorExternalMutationRevision &+= 1
            currentContentBinding.wrappedValue = output
            findStatusMessage = pretty ? "Formatted markup" : "Minified markup"
        } catch ForkDocumentFormatter.FormatError.empty {
            // Nothing to format; stay silent.
        } catch {
            findStatusMessage = "Could not format markup."
        }
    }

    // MARK: - Line-ending conversion

    func forkConvertLineEndings(to target: ForkLineEnding) {
        let source = currentContentBinding.wrappedValue
        let converted = ForkLineEndingConverter.convert(source, to: target)
        guard converted != source else {
            findStatusMessage = "Line endings already \(target.shortLabel)"
            return
        }
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = converted
        findStatusMessage = "Converted line endings to \(target.shortLabel)"
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
        findStatusMessage = "Copied document text"
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
