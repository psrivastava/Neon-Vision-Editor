//
//  BreadcrumbBar.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Breadcrumb path bar (task 6). Shows the active file's path as chevron-separated segments plus a
//  language badge, with a context menu: Copy Path, Copy Name, Reveal in Finder (macOS).
//  Self-contained; inserted above the editor behind the SettingsForkShowBreadcrumbBar toggle.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A single breadcrumb: the trailing path components of the file plus a language badge.
/// Value-typed and side-effect-free except for the explicit pasteboard / Finder actions.
struct ForkBreadcrumbBar: View {
    let fileURL: URL?
    let language: String

    /// Show at most this many trailing path components to keep the bar compact.
    private let maxSegments = 4

    var body: some View {
        HStack(spacing: 4) {
            if let fileURL {
                ForEach(Array(segments(for: fileURL).enumerated()), id: \.offset) { index, segment in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    Text(segment)
                        .font(.system(size: 11))
                        .foregroundStyle(index == segments(for: fileURL).count - 1 ? .primary : .secondary)
                        .lineLimit(1)
                }
            } else {
                Text("Untitled")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !language.isEmpty, language.lowercased() != "plain" {
                Text(language.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .contextMenu { contextMenuItems }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Segments

    private func segments(for url: URL) -> [String] {
        let components = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        guard components.count > maxSegments else { return components }
        return Array(components.suffix(maxSegments))
    }

    private var accessibilityLabel: String {
        guard let fileURL else { return "Breadcrumb: Untitled" }
        return "Breadcrumb: " + segments(for: fileURL).joined(separator: ", ")
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        if let fileURL {
            Button("Copy Path") { copyToPasteboard(fileURL.path) }
            Button("Copy Name") { copyToPasteboard(fileURL.lastPathComponent) }
#if os(macOS)
            Button("Reveal in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([fileURL])
            }
#endif
        }
    }

    private func copyToPasteboard(_ string: String) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
#else
        UIPasteboard.general.string = string
#endif
    }
}
