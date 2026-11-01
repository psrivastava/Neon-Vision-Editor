import SwiftUI

extension ContentView {
    var sharedImportItems: [SharedImportStore.Item] {
        guard sharedImportAccessAllowed else { return [] }
        _ = sharedImportsRefreshToken
        return SharedImportStore.items(limit: 5)
    }

    var shareImportsAutoOpenEnabled: Bool {
        UserDefaults.standard.object(forKey: "SettingsShareImportsAutoOpen") as? Bool ?? true
    }

    var sharedImportDestinationMessage: String {
        let count = pendingSharedImportURLs.count
        if count == 1, let name = pendingSharedImportURLs.first?.lastPathComponent {
            return String(format: NSLocalizedString("Choose where to open %@.", comment: "Share import destination"), name)
        }
        return String(format: NSLocalizedString("Choose where to open %d shared items.", comment: "Share import destination"), count)
    }

    var sharedImportOpenNewTabsTitle: String {
        pendingSharedImportURLs.count == 1
            ? NSLocalizedString("Open in New Tab", comment: "Share import action")
            : NSLocalizedString("Open in New Tabs", comment: "Share import action")
    }

    var canReplaceCurrentTabWithPendingSharedImport: Bool {
        guard pendingSharedImportURLs.count == 1,
              let tab = viewModel.selectedTab,
              !tab.isLoadingContent,
              tab.isReadOnlyPreview != true else {
            return false
        }
        return true
    }

    var startupRecentFiles: [RecentFilesStore.Item] {
        _ = recentFilesRefreshToken
        return RecentFilesStore.items(limit: 5)
    }

    var shouldShowStartupRecentFilesCard: Bool {
        guard showRecentFilesOnEmptyDocuments else { return false }
        guard !brainDumpLayoutEnabled else { return false }
        #if os(macOS)
        if viewModel.tabs.isEmpty {
            return !startupRecentFiles.isEmpty || !sharedImportItems.isEmpty
        }
        #endif
        // Active-tab-only gate: a `+`-opened blank tab (count > 1) still
        // qualifies, matching the welcome card so the two render together.
        guard let tab = viewModel.selectedTab else { return false }
        guard !tab.isLoadingContent else { return false }
        guard tab.fileURL == nil else { return false }
        guard tab.document.utf16Length == 0 else { return false }
        return !startupRecentFiles.isEmpty || !sharedImportItems.isEmpty
    }

    var shouldShowSafeModeStartupCard: Bool {
        guard startupBehavior == .safeMode else { return false }
        guard !brainDumpLayoutEnabled else { return false }
        guard viewModel.tabs.count == 1 else { return false }
        guard let tab = viewModel.selectedTab else { return false }
        guard !tab.isLoadingContent else { return false }
        return tab.fileURL == nil
    }

    /// NotepadMac-style welcome card for an empty, unsaved document — shown
    /// whenever the current tab is blank, independent of whether recent files
    /// exist, so a brand-new install still gets guidance.
    var shouldShowWelcomeCard: Bool {
        guard !brainDumpLayoutEnabled else { return false }
        #if os(macOS)
        if viewModel.tabs.isEmpty { return true }
        #endif
        // The active tab is blank — count of other tabs is irrelevant; the
        // welcome card shows whenever this specific tab has nothing in it.
        guard let tab = viewModel.selectedTab else { return false }
        guard !tab.isLoadingContent else { return false }
        guard tab.fileURL == nil else { return false }
        return tab.document.utf16Length == 0
    }

    var shouldShowStartupOverlay: Bool {
        shouldShowSafeModeStartupCard || shouldShowStartupRecentFilesCard || shouldShowWelcomeCard
    }

    @ViewBuilder
    var startupOverlay: some View {
        // ScrollView keeps the welcome stack inside the editor pane. Without
        // it the content exceeds available height and bleeds over the title
        // row and the status bar. `.clipped()` on the outer frame also
        // defends against hosting-view overflow.
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 20) {
                if shouldShowSafeModeStartupCard {
                    safeModeStartupCard
                }
                if shouldShowWelcomeCard {
                    welcomeCard
                }
                if shouldShowStartupRecentFilesCard {
                    if !sharedImportItems.isEmpty {
                        startupSharedImportsCard
                    }
                    if !startupRecentFiles.isEmpty {
                        startupRecentFilesCard
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// App identity + four quick actions, matching the NotepadMac layout.
    var welcomeCard: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
#if os(macOS)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 76, height: 76)
#else
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Color.accentColor)
#endif
                Text("Neon Editor")
                    .font(.system(size: 24, weight: .semibold))
                Text("Lightweight text editor for macOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 2) {
                welcomeAction(symbol: "doc.badge.plus", title: "New File",
                              shortcut: "⌘N") { viewModel.addNewTab() }
                welcomeAction(symbol: "folder", title: "Open File",
                              shortcut: "⌘O") { openFileFromToolbar() }
#if os(macOS)
                welcomeAction(symbol: "folder.badge.plus", title: "Open Folder in Sidebar",
                              shortcut: "⌘⇧O") { openProjectFolder() }
                welcomeAction(symbol: "command", title: "Command Palette",
                              shortcut: "⌘⇧P") {
                    NotificationCenter.default.post(name: .forkShowCommandPaletteRequested, object: nil)
                }
#endif
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
        .frame(maxWidth: 460)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome to Neon Vision Editor")
    }

    private func welcomeAction(symbol: String, title: String, shortcut: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14))
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.primary.opacity(0.001)) // hoverable without a visible fill
        )
        .accessibilityLabel("\(title), \(shortcut)")
    }

    var safeModeStartupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Safe Mode", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(Color.orange)

            Text(safeModeMessage ?? "Safe Mode is active for this launch.")
                .font(.subheadline)
                .foregroundStyle(.primary)

            Text("Neon Vision Editor started with a blank document and temporarily paused heavier startup features so you can recover safely.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if safeModeRecoveryPreparedForNextLaunch {
                Text("Normal startup will be used again on the next launch.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                Button("Open File…") {
                    openFileFromToolbar()
                }
                .font(.subheadline.weight(.semibold))

                Button("Normal Next Launch") {
                    RuntimeReliabilityMonitor.shared.clearSafeModeRecoveryState()
                    safeModeRecoveryPreparedForNextLaunch = true
                }
                .font(.subheadline.weight(.semibold))

#if os(macOS)
                Button("Settings…") {
                    openSettings(tab: "general")
                }
                .font(.subheadline.weight(.semibold))
#endif
            }
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Safe Mode startup")
    }

    var startupRecentFilesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Recent Files")
                .font(.headline)

            ForEach(startupRecentFiles) { item in
                HStack(spacing: 12) {
                    Button {
                        _ = viewModel.openFile(url: item.url)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)

                    Button {
                        RecentFilesStore.togglePinned(item.url)
                    } label: {
                        Image(systemName: item.isPinned ? "star.fill" : "star")
                            .foregroundStyle(item.isPinned ? Color.yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.isPinned ? "Unpin recent file" : "Pin recent file")
                    .accessibilityHint("Keeps this file near the top of recent files")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )
            }

            Button("Open File…") {
                openFileFromToolbar()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recent files")
    }

    var startupSharedImportsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Shared Imports")
                .font(.headline)

            ForEach(sharedImportItems) { item in
                Button {
                    _ = viewModel.openFile(url: item.url)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .lineLimit(1)
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )
                .accessibilityLabel("Open shared import \(item.title)")
            }

            Button("Clear Import History") {
                SharedImportStore.clearHistory()
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(20)
        .frame(maxWidth: 520)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 16, x: 0, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shared imports")
    }

    func openSharedImportURLs(_ urls: [URL]) {
        SharedImportStore.remember(urls)
        guard shareImportsAutoOpenEnabled else { return }
        for url in urls {
            _ = viewModel.openFile(url: url)
        }
    }

    func promptForSharedImportDestination(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        SharedImportStore.remember(urls)
        pendingSharedImportURLs = urls
        showSharedImportDestinationDialog = true
        sharedImportsRefreshToken = UUID()
    }

    func handleSharedImportURL(_ url: URL) {
        let importedURLs = ShareImportHandoff.importedFileURLs(from: url)
        let urls = importedURLs.isEmpty ? ShareImportHandoff.consumePendingImportedFileURLs() : importedURLs
        guard sharedImportAccessAllowed else {
            pendingSharedImportURL = urls.isEmpty ? url : nil
            pendingSharedImportURLs = urls
            if !urls.isEmpty || pendingSharedImportURL != nil {
                showSharedImportAccessExplanation = true
            }
            return
        }
        promptForSharedImportDestination(urls)
    }

    func consumePendingSharedImportsIfNeeded() {
        let urls = ShareImportHandoff.consumePendingImportedFileURLs()
        guard !urls.isEmpty else { return }
        guard sharedImportAccessAllowed else {
            pendingSharedImportURL = nil
            pendingSharedImportURLs = urls
            showSharedImportAccessExplanation = true
            return
        }
        promptForSharedImportDestination(urls)
    }

    func confirmSharedImportAccess() {
        sharedImportAccessAllowed = true
        if !pendingSharedImportURLs.isEmpty {
            let urls = pendingSharedImportURLs
            pendingSharedImportURLs = []
            promptForSharedImportDestination(urls)
            return
        }
        guard let url = pendingSharedImportURL else {
            sharedImportsRefreshToken = UUID()
            return
        }
        pendingSharedImportURL = nil
        promptForSharedImportDestination(ShareImportHandoff.importedFileURLs(from: url))
    }

    func cancelSharedImportAccess() {
        pendingSharedImportURL = nil
        pendingSharedImportURLs = []
        showSharedImportAccessExplanation = false
    }

    func openPendingSharedImportsInNewTabs() {
        let urls = pendingSharedImportURLs
        pendingSharedImportURLs = []
        showSharedImportDestinationDialog = false
        for url in urls {
            _ = viewModel.openFile(url: url)
        }
    }

    func replaceCurrentTabWithPendingSharedImport() {
        guard let url = pendingSharedImportURLs.first else {
            cancelPendingSharedImportDestination()
            return
        }
        pendingSharedImportURLs = []
        showSharedImportDestinationDialog = false
        _ = viewModel.replaceSelectedTabWithFile(url: url)
    }

    func cancelPendingSharedImportDestination() {
        pendingSharedImportURLs = []
        showSharedImportDestinationDialog = false
    }
}
