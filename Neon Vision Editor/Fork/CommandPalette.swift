//
//  CommandPalette.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Command palette (Cmd+Shift+P, task 5). A self-contained floating NSPanel hosting a SwiftUI list,
//  distinct from Quick Open (Cmd+P = files). Selecting a command posts its notification and closes.
//
//  macOS-only. Presented via a shared controller that observes `.forkShowCommandPaletteRequested`,
//  so upstream ContentView needs no new @State — the only hook is installing the observer once.
//

#if os(macOS)
import AppKit
import SwiftUI

/// Installs a single app-wide observer that shows the palette on request. Call once at launch.
@MainActor
enum ForkCommandPaletteInstaller {
    private static var installed = false

    static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(
            forName: .forkShowCommandPaletteRequested,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { ForkCommandPaletteController.shared.toggle() }
        }
    }
}

/// Owns the palette panel lifecycle (one shared instance).
@MainActor
final class ForkCommandPaletteController {
    static let shared = ForkCommandPaletteController()
    private var panel: NSPanel?

    func toggle() {
        if let panel, panel.isVisible {
            close()
        } else {
            show()
        }
    }

    private func show() {
        // Capture the window that was key BEFORE the palette steals focus, so commands route back to it.
        let targetWindowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber

        let root = ForkCommandPaletteView(
            targetWindowNumber: targetWindowNumber,
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingController(rootView: root)
        let panel = NSPanel(contentViewController: hosting)
        panel.styleMask = [.titled, .fullSizeContentView, .nonactivatingPanel]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = true
        panel.level = .floating
        panel.setContentSize(NSSize(width: 560, height: 420))
        panel.center()
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// SwiftUI content: a search field over the command registry with keyboard navigation.
private struct ForkCommandPaletteView: View {
    let targetWindowNumber: Int?
    let onClose: () -> Void

    @State private var query = ""
    @State private var selectedIndex = 0
    // FORK: focus the search field the moment the palette opens so the user can type immediately
    // (previously the panel opened with no first responder — you had to click the field first).
    @FocusState private var queryFieldFocused: Bool
    private let allCommands = ForkCommandRegistry.allCommands()

    private var filtered: [ForkCommand] {
        ForkCommandRegistry.filter(allCommands, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Run a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .padding(12)
                .focused($queryFieldFocused)
                .onChange(of: query) { _, _ in selectedIndex = 0 }
                .onSubmit { runSelected() }
                // FORK: the focused field is first responder and swallows Escape before the background
                // KeyCatcherView sees it, so Cmd+Shift+P wouldn't dismiss on Esc. Handle Escape on the
                // field itself (macOS 14+ onKeyPress) — arrow/enter still flow to the KeyHandler.
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }

            Divider()

            ScrollViewReader { proxy in
                List(Array(filtered.enumerated()), id: \.element.id) { index, command in
                    HStack {
                        Text(command.title)
                        Spacer()
                        Text(command.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .listRowBackground(index == selectedIndex ? Color.accentColor.opacity(0.2) : Color.clear)
                    .id(index)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedIndex = index; runSelected() }
                }
                .onChange(of: selectedIndex) { _, newValue in
                    withAnimation(.linear(duration: 0.05)) { proxy.scrollTo(newValue, anchor: .center) }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
        .onAppear {
            // Delay one tick so the NSPanel has finished becoming key before we grab focus,
            // otherwise SwiftUI drops the focus assignment and the field opens unfocused.
            DispatchQueue.main.async { queryFieldFocused = true }
        }
        .background(KeyHandler(
            onMoveDown: { moveSelection(1) },
            onMoveUp: { moveSelection(-1) },
            onEnter: { runSelected() },
            onEscape: { onClose() }
        ))
    }

    private func moveSelection(_ delta: Int) {
        guard !filtered.isEmpty else { return }
        selectedIndex = max(0, min(filtered.count - 1, selectedIndex + delta))
    }

    private func runSelected() {
        guard filtered.indices.contains(selectedIndex) else { return }
        let command = filtered[selectedIndex]
        onClose()
        var userInfo: [AnyHashable: Any] = [:]
        if let targetWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = targetWindowNumber
        }
        // Delay so the palette is fully dismissed and focus returns before the command runs.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: command.notification,
                object: command.object,
                userInfo: userInfo.isEmpty ? nil : userInfo
            )
        }
    }
}

/// Bridges arrow/enter/escape key events from AppKit into SwiftUI closures.
private struct KeyHandler: NSViewRepresentable {
    let onMoveDown: () -> Void
    let onMoveUp: () -> Void
    let onEnter: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyCatcherView {
        let view = KeyCatcherView()
        view.onMoveDown = onMoveDown
        view.onMoveUp = onMoveUp
        view.onEnter = onEnter
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: KeyCatcherView, context: Context) {}

    final class KeyCatcherView: NSView {
        var onMoveDown: (() -> Void)?
        var onMoveUp: (() -> Void)?
        var onEnter: (() -> Void)?
        var onEscape: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 125: onMoveDown?()   // down arrow
            case 126: onMoveUp?()     // up arrow
            case 36, 76: onEnter?()   // return / enter
            case 53: onEscape?()      // escape
            default: super.keyDown(with: event)
            }
        }
    }
}
#endif
