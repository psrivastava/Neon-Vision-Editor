//
//  PreviewOrientation.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Preview orientation toggle (Batch C, task 8): the markdown/web preview split can sit on the
//  RIGHT (side panel — upstream default) or at the BOTTOM (both editor and preview get full width).
//
//  Isolation strategy (Option X): all orientation logic lives here. Upstream `editorView` in
//  ContentView.swift needs a single `// MARK: - FORK` hook that wraps the editor column in
//  `forkEditorPreviewSplit { … }`; the preview panes/transitions move out of upstream into this
//  file. Every preview member this file references (markdownPreviewPane, webPreviewPane,
//  markdownPreviewSplitPane, webPreviewSplitPane, markdownPreviewSplitTransition, iOSPaneDivider,
//  editorSurfaceBackgroundStyle) is already `internal`, so no upstream preview code is touched.
//

import SwiftUI

/// Where the preview split sits relative to the editor. Persisted via
/// `@AppStorage("SettingsForkPreviewOrientation")` (default `.side`, matching upstream behavior).
enum ForkPreviewOrientation: String, CaseIterable, Sendable {
    case side   // preview on the right (upstream default)
    case bottom // preview beneath the editor; both panes get full width

    var title: String {
        switch self {
        case .side: return "Side (Right)"
        case .bottom: return "Bottom"
        }
    }
}

// MARK: - Editor + preview split arrangement

extension ContentView {

    /// Wrap the editor column and the (optional) preview split into an orientation-aware layout.
    /// The single upstream hook in `editorView` calls this with the editor `VStack` as its content;
    /// this property decides whether the preview sits beside (side) or beneath (bottom) the editor.
    func forkEditorPreviewSplit<EditorColumn: View>(
        @ViewBuilder editorColumn: @escaping () -> EditorColumn
    ) -> some View {
        ForkPreviewSplitLayout(
            previewVisible: isMarkdownPreviewSplitVisible || isWebPreviewSplitVisible,
            editor: editorColumn,
            sideTransition: { forkSideSplitTransition },
            sidePreview: { forkSideSplitPane },
            bottomTransition: { forkBottomSplitTransition },
            bottomPreview: { forkBottomSplitPane }
        )
    }

    // MARK: Side (upstream) orientation — unchanged panes/transition, just relocated here

    @ViewBuilder
    fileprivate var forkSideSplitTransition: some View {
#if os(iOS) || os(visionOS)
        iOSPaneDivider
#else
        markdownPreviewSplitTransition
#endif
    }

    @ViewBuilder
    fileprivate var forkSideSplitPane: some View {
        if isMarkdownPreviewSplitVisible {
            markdownPreviewSplitPane
        } else if isWebPreviewSplitVisible {
            webPreviewSplitPane
        }
    }

    // MARK: Bottom orientation — height-capped pane + horizontal transition (fork-only)

    @ViewBuilder
    fileprivate var forkBottomSplitTransition: some View {
        LinearGradient(
            stops: [
                .init(color: Color.secondary.opacity(0.10), location: 0),
                .init(color: Color.secondary.opacity(0.035), location: 0.45),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 10)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    fileprivate var forkBottomSplitPane: some View {
        if isMarkdownPreviewSplitVisible {
            forkBottomPreviewPane { markdownPreviewPane }
        } else if isWebPreviewSplitVisible {
            forkBottomPreviewPane { webPreviewPane }
        }
    }

    /// Bottom-panel styling: mirrors upstream `previewSplitPane` but caps height instead of width
    /// and rounds the top corners (a bottom panel visually attaches to the editor above it).
    @ViewBuilder
    fileprivate func forkBottomPreviewPane<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 16,
            bottomLeadingRadius: 10,
            bottomTrailingRadius: 10,
            topTrailingRadius: 16,
            style: .continuous
        )
        content()
            .frame(maxWidth: .infinity, minHeight: 200, idealHeight: 300, maxHeight: 460)
            .background(editorSurfaceBackgroundStyle)
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 4)
            .padding(.bottom, 4)
    }
}

// MARK: - Control surface (toolbar flyout)

extension ContentView {
    /// A compact orientation picker shown beside the preview toggle in the toolbar. Only meaningful
    /// while a preview is visible, so the upstream call site gates it on `isPreviewVisible`.
    @ViewBuilder
    var forkPreviewOrientationControl: some View {
        ForkPreviewOrientationMenu()
    }
}

/// Owns the orientation `@AppStorage` for the toolbar flyout (an extension can't hold state).
private struct ForkPreviewOrientationMenu: View {
    @AppStorage("SettingsForkPreviewOrientation") private var orientationRaw = ForkPreviewOrientation.side.rawValue

    var body: some View {
        Menu {
            Picker("Preview Position", selection: $orientationRaw) {
                ForEach(ForkPreviewOrientation.allCases, id: \.rawValue) { orientation in
                    Label(orientation.title, systemImage: iconName(for: orientation))
                        .tag(orientation.rawValue)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "rectangle.split.2x1")
        } primaryAction: {
            // Primary click cycles side ↔ bottom for quick toggling; the flyout picks explicitly.
            let current = ForkPreviewOrientation(rawValue: orientationRaw) ?? .side
            orientationRaw = (current == .side ? ForkPreviewOrientation.bottom : .side).rawValue
        }
#if os(macOS)
        .menuStyle(.borderlessButton)
        .fixedSize()
#endif
        .help("Preview Position (Side or Bottom)")
        .accessibilityLabel("Preview Position")
    }

    private func iconName(for orientation: ForkPreviewOrientation) -> String {
        switch orientation {
        case .side: return "rectangle.righthalf.inset.filled"
        case .bottom: return "rectangle.bottomhalf.inset.filled"
        }
    }
}

// MARK: - Layout container

/// Owns the orientation `@AppStorage` so a change redraws the split immediately (an extension can't
/// hold stored state). Only the selected orientation's preview closure is evaluated, so the hidden
/// orientation never instantiates a WebView.
private struct ForkPreviewSplitLayout<
    Editor: View,
    SideTransition: View,
    SidePreview: View,
    BottomTransition: View,
    BottomPreview: View
>: View {
    @AppStorage("SettingsForkPreviewOrientation") private var orientationRaw = ForkPreviewOrientation.side.rawValue

    let previewVisible: Bool
    @ViewBuilder let editor: () -> Editor
    @ViewBuilder let sideTransition: () -> SideTransition
    @ViewBuilder let sidePreview: () -> SidePreview
    @ViewBuilder let bottomTransition: () -> BottomTransition
    @ViewBuilder let bottomPreview: () -> BottomPreview

    var body: some View {
        let orientation = ForkPreviewOrientation(rawValue: orientationRaw) ?? .side
        if previewVisible && orientation == .bottom {
            // Editor above, preview beneath — both get the full width of this HStack slot.
            VStack(spacing: 0) {
                editor()
                bottomTransition()
                bottomPreview()
            }
        } else if previewVisible {
            // Side panel (upstream layout): editor and preview are horizontal siblings.
            HStack(spacing: 0) {
                editor()
                sideTransition()
                sidePreview()
            }
        } else {
            editor()
        }
    }
}
