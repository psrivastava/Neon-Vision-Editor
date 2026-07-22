//
//  ContentView+Commands.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Editor-side handlers for fork commands. Lives in a fork file (not upstream ContentView+Actions)
//  so upstream merges stay clean. Mirrors the existing markdown-formatting apply pattern:
//  read active editor selection → transform → replace → reclassify/refresh.
//

import SwiftUI

extension ContentView {

    /// Attach fork command observers to the view. Called from the upstream observer chain via a
    /// single `// MARK: - FORK` hook in ContentView.swift.
    func withForkCommands<Content: View>(_ view: Content) -> some View {
        view
            .onReceive(NotificationCenter.default.publisher(for: .forkApplyStringTransformRequested)) { notif in
                guard forkMatchesWindow(notif) else { return }
                guard let raw = notif.object as? String,
                      let transform = ForkStringTransform(rawValue: raw) else { return }
                forkApplyStringTransform(transform)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkFormatMarkupRequested)) { notif in
                guard forkMatchesWindow(notif) else { return }
                forkFormatMarkup(pretty: true)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkMinifyMarkupRequested)) { notif in
                guard forkMatchesWindow(notif) else { return }
                forkFormatMarkup(pretty: false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkCopyAsRichTextRequested)) { notif in
                guard forkMatchesWindow(notif) else { return }
                forkCopyAsRichText()
            }
            .onReceive(NotificationCenter.default.publisher(for: .forkConvertLineEndingsRequested)) { notif in
                guard forkMatchesWindow(notif) else { return }
                guard let raw = notif.object as? String,
                      let target = ForkLineEnding(rawValue: raw) else { return }
                forkConvertLineEndings(to: target)
            }
    }

    // MARK: - Breadcrumb bar (task 6)

    /// Breadcrumb bar shown above the editor, gated by the SettingsForkShowBreadcrumbBar toggle
    /// (default on). Reads the active tab's file URL + language. Empty view when disabled or in
    /// brain-dump layout to avoid chrome in the distraction-free mode.
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

    // MARK: - Line-ending conversion (task 7)

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

    // MARK: - Window routing

    /// Fork mirror of the upstream per-window filter. On iOS there is a single window, so always true.
    private func forkMatchesWindow(_ notif: Notification) -> Bool {
#if os(macOS)
        guard let target = notif.userInfo?[EditorCommandUserInfo.windowNumber] as? Int else { return true }
        return target == hostWindowNumber
#else
        return true
#endif
    }

    // MARK: - String transforms (task 1)

    /// Apply a transform to the current selection, or to the whole document when nothing is selected.
    func forkApplyStringTransform(_ transform: ForkStringTransform) {
#if os(macOS)
        guard let textView = activeEditorTextView(), let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let targetRange = selection.length > 0 ? selection : NSRange(location: 0, length: storage.length)
        guard NSMaxRange(targetRange) <= storage.length else { return }

        let source = (storage.string as NSString).substring(with: targetRange)
        let result = transform.apply(to: source)
        guard result != source else {
            findStatusMessage = "\(transform.title): no change"
            return
        }

        storage.beginEditing()
        storage.replaceCharacters(in: targetRange, with: result)
        storage.endEditing()
        let newSelection = NSRange(location: targetRange.location, length: (result as NSString).length)
        textView.setSelectedRange(forkClampedSelection(newSelection, textLength: storage.length))
        textView.didChangeText()
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = textView.string
        findStatusMessage = "Applied \(transform.title)"
        textView.window?.makeFirstResponder(textView)
#else
        // On iOS/iPadOS, transform the whole document via the content binding.
        let source = currentContentBinding.wrappedValue
        let result = transform.apply(to: source)
        guard result != source else { return }
        editorExternalMutationRevision &+= 1
        currentContentBinding.wrappedValue = result
#endif
    }

    // MARK: - Markup formatting (task 2)

    func forkFormatMarkup(pretty: Bool) {
        guard ForkDocumentFormatter.handles(language: currentLanguage) else {
            findStatusMessage = "Formatting is available for XML, HTML, and SVG documents."
            return
        }
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

    // MARK: - Copy as HTML / Rich Text (task 3)

    /// Copy the highlighted selection (or whole document) as both HTML and RTF pasteboard flavors,
    /// preserving syntax-highlight attributes already applied to the text view.
    func forkCopyAsRichText() {
#if os(macOS)
        guard let textView = activeEditorTextView(),
              let storage = textView.textStorage else { return }
        let selection = textView.selectedRange()
        let range = selection.length > 0 ? selection : NSRange(location: 0, length: storage.length)
        guard NSMaxRange(range) <= storage.length, range.length > 0 else { return }
        let attributed = storage.attributedSubstring(from: range)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wroteRich = false
        if let rtf = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pasteboard.setData(rtf, forType: .rtf)
            wroteRich = true
        }
        if let html = try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ) {
            pasteboard.setData(html, forType: .html)
            wroteRich = true
        }
        // Always include a plain-text flavor as a fallback for plain-text targets.
        pasteboard.setString(attributed.string, forType: .string)
        findStatusMessage = wroteRich ? "Copied as rich text" : "Copied as text"
#endif
    }

    // MARK: - Helpers

    private func forkClampedSelection(_ selection: NSRange, textLength: Int) -> NSRange {
        let location = min(max(0, selection.location), textLength)
        let length = min(max(0, selection.length), textLength - location)
        return NSRange(location: location, length: length)
    }
}
