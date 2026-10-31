import SwiftUI

#if os(macOS)
import AppKit
#endif

extension ContentView {
    @ViewBuilder
    var projectStructureSidebarPanel: some View {
#if os(macOS)
        projectStructureSidebarBody
            .frame(
                minWidth: clampedProjectSidebarWidth,
                idealWidth: clampedProjectSidebarWidth,
                maxWidth: clampedProjectSidebarWidth
            )
#else
        projectStructureSidebarBody
            .frame(
                minWidth: clampedProjectSidebarWidth,
                idealWidth: clampedProjectSidebarWidth,
                maxWidth: clampedProjectSidebarWidth
            )
            .background(editorSurfaceBackgroundStyle)
#endif
    }

    var projectSidebarResizeHandle: some View {
        // Global space: the handle moves as the width changes, so a local
        // translation feeds back into itself and the layout oscillates.
        let drag = DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let startWidth = projectSidebarResizeStartWidth ?? clampedProjectSidebarWidth
                if projectSidebarResizeStartWidth == nil {
                    projectSidebarResizeStartWidth = startWidth
                }
                let delta = value.translation.width
                let proposed: CGFloat
                switch projectNavigatorPlacement {
                case .leading:
                    proposed = startWidth + delta
                case .trailing:
                    proposed = startWidth - delta
                }
                let clamped = min(max(proposed, minimumProjectSidebarWidth), maximumProjectSidebarWidth)
                projectSidebarWidth = Double(clamped)
            }
            .onEnded { _ in
                projectSidebarResizeStartWidth = nil
#if os(macOS)
                isProjectSidebarResizeHandleHovered = false
                MacSidebarResizeCursor.reset(ownerID: "project-sidebar")
#endif
            }

#if os(macOS)
        return MacSidebarResizeDivider(
            visibleWidth: projectSidebarResizeHandleWidth,
            hitTargetWidth: projectSidebarResizeHitTargetWidth,
            cursorOwnerID: "project-sidebar",
            accentWidth: projectSidebarResizeHandleAccentWidth,
            accentColor: projectSidebarHandleAccentColor,
            surfaceStyle: AnyShapeStyle(Color.clear), // backdrop gutter shows through
            topSurfaceStyle: AnyShapeStyle(Color.clear), // FORK: no NSToolbar band
            isActive: projectSidebarResizeHandleIsActive,
            isDragging: projectSidebarResizeStartWidth != nil,
            isHovered: $isProjectSidebarResizeHandleHovered,
            drag: drag,
            accessibilityLabel: "Resize Project Sidebar",
            accessibilityHint: "Drag left or right to adjust project sidebar width",
            accessibilityAdjust: { direction in
                let delta: CGFloat = direction == .increment ? 24 : -24
                let adjusted = min(
                    max(CGFloat(projectSidebarWidth) + delta, minimumProjectSidebarWidth),
                    maximumProjectSidebarWidth
                )
                projectSidebarWidth = Double(adjusted)
            },
            hitTargetBias: projectNavigatorPlacement == .trailing ? 1 : -1,
            onNativeDrag: { dx in
                let start = projectSidebarResizeStartWidth ?? clampedProjectSidebarWidth
                if projectSidebarResizeStartWidth == nil { projectSidebarResizeStartWidth = start }
                // Trailing panel grows as the handle moves left.
                let proposed = projectNavigatorPlacement == .trailing ? start - dx : start + dx
                projectSidebarWidth = Double(min(max(proposed, minimumProjectSidebarWidth), maximumProjectSidebarWidth))
            },
            onNativeDragEnded: {
                projectSidebarResizeStartWidth = nil
                isProjectSidebarResizeHandleHovered = false
                MacSidebarResizeCursor.reset(ownerID: "project-sidebar")
            }
        )
#else
        return ZStack {
            Rectangle()
                .fill(Color.clear)
            Rectangle()
                .fill(projectSidebarHandleAccentColor)
                .frame(width: projectSidebarResizeHandleAccentWidth)
                .clipShape(Capsule())
                .padding(.vertical, projectSidebarResizeHandleIsActive ? 30 : 0)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: projectSidebarResizeHandleWidth)
        .background(projectSidebarHandleSurfaceStyle)
        .contentShape(Rectangle())
        .gesture(drag)
        .accessibilityElement()
        .accessibilityLabel("Resize Project Sidebar")
        .accessibilityHint("Drag left or right to adjust project sidebar width")
#endif
    }

    var projectSidebarHandleAccentColor: Color {
#if os(macOS)
        return projectSidebarResizeHandleIsActive
            ? Color.accentColor.opacity(0.55)
            : Color.clear
#else
        let isActive = projectSidebarResizeHandleIsActive
        return isActive ? Color.accentColor.opacity(0.70) : projectSidebarHandleDividerColor
#endif
    }

    var projectSidebarResizeHandleAccentWidth: CGFloat {
#if os(macOS)
        projectSidebarResizeHandleIsActive ? 2 : 0
#else
        projectSidebarResizeHandleIsActive ? 2.5 : 1.5
#endif
    }

    var projectSidebarHandleDividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.30) : Color.black.opacity(0.22)
    }

    var projectSidebarResizeHandleIsActive: Bool {
#if os(macOS)
        isProjectSidebarResizeHandleHovered || projectSidebarResizeStartWidth != nil
#else
        projectSidebarResizeStartWidth != nil
#endif
    }

    var projectSidebarHandleSurfaceStyle: AnyShapeStyle {
#if os(macOS)
        return macResizeHandleSurfaceStyle
#else
        if enableTranslucentWindow {
            return editorSurfaceBackgroundStyle
        }
        return useIOSUnifiedSolidSurfaces
            ? AnyShapeStyle(iOSNonTranslucentSurfaceColor)
            : AnyShapeStyle(Color.clear)
#endif
    }

    /// The resize hit target must use the same surface as the adjacent panes.
    /// Keeping the material here avoids a visible strip or desktop bleed-through
    /// at the 11-point interaction boundary.
    var macResizeHandleSurfaceStyle: AnyShapeStyle {
#if os(macOS)
        editorSurfaceBackgroundStyle
#else
        AnyShapeStyle(Color.clear)
#endif
    }

    func utilitySidebarHeader(integratedIntoProjectCard: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: utilitySidebarMode.symbolName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .background(
                        Color.accentColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(utilitySidebarMode.headerTitle)
                        .font(.headline.weight(.semibold))
                    Text(utilitySidebarMode.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
                // macOS: the toggle lives in the editor title row so it
                // survives collapse.
            }

            Picker("Sidebar Content", selection: Binding(
                get: { utilitySidebarMode },
                set: { utilitySidebarModeRaw = $0.rawValue }
            )) {
                ForEach(UtilitySidebarMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.regular)
            .tint(.accentColor)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, integratedIntoProjectCard ? 0 : 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sidebar Content")
        .accessibilityHint("Choose Project or AI Assistant")
    }

    var utilitySidebarHeaderTopInset: CGFloat {
        // The header already carries its own top padding (see
        // utilitySidebarHeader's .padding(.top, 10)); adding more here
        // made the Assistant tab sit lower than the Project tab's header,
        // which doesn't get this extra inset.
        0
    }

    /// Keeps the AI tab on the same inset card surface as the project browser.
    /// The project browser owns this treatment internally, while the AI view is
    /// composed from a header and chat body and therefore needs the same shell
    /// at this level.
    var aiChatSidebarPanelContent: some View {
        VStack(spacing: 0) {
            utilitySidebarHeader()
                .padding(.top, utilitySidebarHeaderTopInset)
            aiChatSidebarBody
                .padding(.top, 8)
        }
        .background(
            utilitySidebarSurfaceFill,
            in: RoundedRectangle(cornerRadius: utilitySidebarCornerRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: utilitySidebarCornerRadius, style: .continuous)
                .stroke(utilitySidebarSurfaceStroke, lineWidth: 1.2)
        }
        .clipShape(RoundedRectangle(cornerRadius: utilitySidebarCornerRadius, style: .continuous))
        .padding(utilitySidebarOuterPadding)
    }

    /// Matches ProjectStructureSidebarView's fill in each platform and window
    /// translucency mode, so switching between Project and AI does not change
    /// the panel surface.
    private var utilitySidebarSurfaceFill: AnyShapeStyle {
        if enableTranslucentWindow {
#if os(macOS)
            return AnyShapeStyle(Color.clear)
#else
            return AnyShapeStyle(.ultraThinMaterial)
#endif
        }
#if os(macOS)
        // One elevation step off the editor surface (see panelCardFill).
        return AnyShapeStyle(ForkSurfaceStyle.panelCardFill(
            themeBackground: currentEditorTheme(colorScheme: colorScheme).background,
            isDark: colorScheme == .dark))
#else
        return AnyShapeStyle(currentEditorTheme(colorScheme: colorScheme).background)
#endif
    }

    private var utilitySidebarSurfaceStroke: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.08)
    }

    private var utilitySidebarCornerRadius: CGFloat {
#if os(macOS)
        12
#else
        20
#endif
    }

    private var utilitySidebarOuterPadding: EdgeInsets {
        // Shell redesign: the window shell provides the backdrop gutters.
        EdgeInsets()
    }

    var projectStructureSidebarBody: some View {
        VStack(spacing: 0) {
            if utilitySidebarMode == .assistant {
                aiChatSidebarPanelContent
            } else {
                ProjectStructureSidebarView(
                    rootFolderURL: projectRootFolderURL,
                    nodes: projectTreeNodes,
                    selectedFileURL: viewModel.selectedTab?.fileURL,
                    showSupportedFilesOnly: showSupportedProjectFilesOnly,
                    showHiddenFiles: showHiddenProjectFiles,
                    ignoredFolderNamesRaw: $projectIgnoredFolderNamesRaw,
                    translucentBackgroundEnabled: enableTranslucentWindow,
                    boundaryEdge: projectNavigatorPlacement == .leading ? .trailing : .leading,
                    onOpenFile: { openFileFromToolbar() },
                    onOpenFolder: { openProjectFolder() },
                    onCloseProjectFolder: { closeProjectFolder() },
                    onCloseProjectFolderAndTabs: { requestCloseProjectFolderAndTabs() },
                    onOpenProjectFolder: { setProjectFolder($0) },
                    onToggleSupportedFilesOnly: { showSupportedProjectFilesOnly = $0 },
                    onToggleHiddenFiles: { showHiddenProjectFiles = $0 },
                    onOpenProjectFile: { url in
                        Task { @MainActor in
                            openProjectFileFromProjectSidebar(url: url)
                        }
                    },
                    onRefreshTree: { refreshProjectBrowserState(showsStatusFeedback: true) },
                    onRevealInFinder: { revealProjectItemInFileBrowser($0) },
                    onCopyPath: { copyProjectItemPath($0) },
                    onCreateProjectFile: { startProjectItemCreation(kind: .file, in: $0) },
                    onCreateProjectFolder: { startProjectItemCreation(kind: .folder, in: $0) },
                    onCreatePythonProject: { startPythonProjectTemplate() },
                    onRenameProjectItem: { startProjectItemRename($0) },
                    onDuplicateProjectItem: { duplicateProjectItem($0) },
                    onDeleteProjectItem: { requestDeleteProjectItem($0) },
                    findInFilesQuery: $findInFilesQuery,
                    findInFilesCaseSensitive: $findInFilesCaseSensitive,
                    findInFilesReplaceQuery: $findInFilesReplaceQuery,
                    findInFilesSelectedMatchIDs: $findInFilesSelectedMatchIDs,
                    findInFilesResults: findInFilesResults,
                    findInFilesStatusMessage: findInFilesStatusMessage,
                    findInFilesSourceMessage: findInFilesSourceMessage,
                    isApplyingFindInFilesReplace: isApplyingFindInFilesReplace,
                    onFindInFilesSearch: { startFindInFiles() },
                    onFindInFilesClear: { clearFindInFiles() },
                    onToggleFindInFilesSelection: { toggleFindInFilesMatchSelection($0) },
                    onSelectAllFindInFilesMatches: { selectAllFindInFilesMatches() },
                    onSelectNoFindInFilesMatches: { clearFindInFilesSelection() },
                    onApplyFindInFilesReplace: { applyProjectWideReplaceFromFindInFiles() },
                    onCancelFindInFilesReplace: { cancelProjectWideReplaceFromFindInFiles() },
                    onSelectFindInFilesMatch: { selectFindInFilesMatch($0) },
                    activateFindInFilesToken: projectSidebarFindInFilesRequestToken,
                    activateTerminalToken: projectSidebarTerminalRequestToken,
                    compareDiffPresentation: sidebarCompareDiffPresentation,
                    onCloseCompareDiff: { sidebarCompareDiffPresentation = nil },
                    revealURL: projectTreeRevealURL,
                    gitFileStatusMap: gitViewModel.fileStatusMap,
                    embeddedHeader: AnyView(utilitySidebarHeader(integratedIntoProjectCard: true)),
                    onLoadDirectory: { directory, completion in
                        refreshProjectTreeSubtree(at: directory, completion: completion)
                    },
                    onExpandAllDirectories: { completion in
                        expandAllProjectDirectories(completion: completion)
                    }
                )
            }
        }
    }

#if os(macOS) && !APP_STORE_BUILD
    @MainActor
    func showTerminalInProjectSidebar() {
        showProjectStructureSidebar = true
        projectSidebarTerminalRequestToken &+= 1
    }
#endif
}

#if os(macOS)
enum MacSidebarResizeCursor {
    private(set) static var activeOwnerID: String?
    private static var generation: UInt = 0

    static func set(ownerID: String) {
        generation &+= 1
        activeOwnerID = ownerID
        NSCursor.resizeLeftRight.set()
    }

    static func reset(ownerID: String) {
        guard activeOwnerID == ownerID else { return }
        generation &+= 1
        activeOwnerID = nil
        NSCursor.arrow.set()
    }

}

struct MacSidebarResizeDivider<ResizeGesture: Gesture>: View where ResizeGesture.Value == DragGesture.Value {
    let visibleWidth: CGFloat
    let hitTargetWidth: CGFloat
    let cursorOwnerID: String
    let accentWidth: CGFloat
    let accentColor: Color
    let surfaceStyle: AnyShapeStyle
    let topSurfaceStyle: AnyShapeStyle
    let isActive: Bool
    let isDragging: Bool
    @Binding var isHovered: Bool
    let drag: ResizeGesture
    let accessibilityLabel: String
    let accessibilityHint: String
    let accessibilityAdjust: ((AccessibilityAdjustmentDirection) -> Void)?
    /// -1 extends the extra hit area leftward, +1 rightward. Point it at the
    /// SwiftUI sidebar, never at the AppKit editor, which wins hit-testing and
    /// swallows the drag.
    var hitTargetBias: CGFloat = 0
    /// When set, AppKit mouse events drive the resize instead of `drag`.
    var onNativeDrag: ((CGFloat) -> Void)? = nil
    var onNativeDragEnded: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Shell redesign: the divider is a transparent gutter — the themed
            // shell backdrop shows through as the gap between cards.
            Rectangle()
                .fill(surfaceStyle)

            VStack(spacing: 0) {
                Rectangle()
                    .fill(topSurfaceStyle)
                    .frame(height: 42)
                Spacer(minLength: 0)
            }

            Rectangle()
                .fill(accentColor)
                .frame(width: accentWidth)
                .clipShape(Capsule())
                .padding(.vertical, isActive ? 26 : 8)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: visibleWidth)
        .overlay {
            MacSidebarResizeCursorTrackingView(
                isHovered: $isHovered,
                isDragging: isDragging,
                cursorOwnerID: cursorOwnerID,
                onNativeDrag: onNativeDrag,
                onNativeDragEnded: onNativeDragEnded
            )
                .frame(width: hitTargetWidth)
                .offset(x: (hitTargetWidth - visibleWidth) / 2 * hitTargetBias)
                .contentShape(Rectangle())
                .gesture(drag, including: onNativeDrag == nil ? .all : .none)
        }
        .zIndex(1)
        .onDisappear {
            isHovered = false
            MacSidebarResizeCursor.reset(ownerID: cursorOwnerID)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityAdjustableAction { direction in
            accessibilityAdjust?(direction)
        }
    }
}

private struct MacSidebarResizeCursorTrackingView: NSViewRepresentable {
    @Binding var isHovered: Bool
    let isDragging: Bool
    let cursorOwnerID: String
    var onNativeDrag: ((CGFloat) -> Void)? = nil
    var onNativeDragEnded: (() -> Void)? = nil

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        view.onHoverChanged = { hovering in
            isHovered = hovering
        }
        view.isDragging = isDragging
        view.cursorOwnerID = cursorOwnerID
        view.onNativeDrag = onNativeDrag
        view.onNativeDragEnded = onNativeDragEnded
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onHoverChanged = { hovering in
            isHovered = hovering
        }
        nsView.isDragging = isDragging
        nsView.cursorOwnerID = cursorOwnerID
        nsView.onNativeDrag = onNativeDrag
        nsView.onNativeDragEnded = onNativeDragEnded
        if isDragging || isHovered {
            MacSidebarResizeCursor.set(ownerID: cursorOwnerID)
        }
    }

    final class TrackingView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        var isDragging: Bool = false
        var cursorOwnerID: String = "resize-handle"
        /// Native drag path: (translation in window points) and end. AppKit
        /// delivers these directly, so neither the window-background drag nor
        /// a neighbouring AppKit view can steal the gesture.
        var onNativeDrag: ((CGFloat) -> Void)?
        var onNativeDragEnded: (() -> Void)?
        private var trackingArea: NSTrackingArea?
        private var dragStartX: CGFloat?

        // The window is movable by its background; a transparent view would
        // otherwise turn a resize drag into a window move.
        override var mouseDownCanMoveWindow: Bool { false }

        override func mouseDown(with event: NSEvent) {
            guard onNativeDrag != nil else { return super.mouseDown(with: event) }
            dragStartX = event.locationInWindow.x
            MacSidebarResizeCursor.set(ownerID: cursorOwnerID)
        }

        override func mouseDragged(with event: NSEvent) {
            guard let start = dragStartX, let onNativeDrag else { return super.mouseDragged(with: event) }
            onNativeDrag(event.locationInWindow.x - start)
        }

        override func mouseUp(with event: NSEvent) {
            guard dragStartX != nil else { return super.mouseUp(with: event) }
            dragStartX = nil
            onNativeDragEnded?()
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited,
                .activeInActiveApp,
                .inVisibleRect
            ]
            let area = NSTrackingArea(rect: .zero, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) {
            onHoverChanged?(true)
            MacSidebarResizeCursor.set(ownerID: cursorOwnerID)
        }

        override func mouseExited(with event: NSEvent) {
            onHoverChanged?(false)
            guard !isDragging else { return }

            MacSidebarResizeCursor.reset(ownerID: cursorOwnerID)
        }
    }
}
#endif
