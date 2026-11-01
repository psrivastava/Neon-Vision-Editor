//
//  PaletteBridge.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Surfaces the fork command catalog inside UPSTREAM's palette (the one titled "Command Palette",
//  backed by `QuickFileSwitcherPanel` / `quickSwitcherItems`).
//
//  Why this exists: the fork shipped its own palette, so there were two palettes with different
//  contents and the fork's format commands were missing from the one people actually open. Rather
//  than fight for a keyboard shortcut, the registry is the single source of truth and this bridge
//  projects it into upstream's list. The standalone fork palette (Cmd+Shift+K) still works and
//  reads from the same registry.
//
//  Upstream seam is two lines: one `append(contentsOf:)` in `quickSwitcherItems`, and one
//  `ForkPaletteBridge.post(...)` in the `default:` arm of `performQuickSwitcherCommand`.
//

import Foundation

extension ContentView {
    /// Upstream-palette seam target: runs a fork command against THIS editor window.
    func forkRunPaletteCommand(_ commandID: String) {
#if os(macOS)
        ForkPaletteBridge.post(commandID, windowNumber: hostWindowNumber)
#else
        ForkPaletteBridge.post(commandID, windowNumber: nil)
#endif
    }
}

enum ForkPaletteBridge {

    /// Prefix that marks a palette id as fork-owned, inside upstream's `cmd:` namespace.
    private static let idPrefix = "cmd:fork."

    /// Registry commands that upstream's palette already offers; listing them twice would just
    /// give every search two identical-looking hits.
    private static let duplicatedByUpstream: Set<String> = [
        "quickOpen", "goToLine", "goToSymbol", "findInFiles", "findReplace", "toggleSidebar"
    ]

    private static var bridgedCommands: [ForkCommand] {
        ForkCommandRegistry.allCommands().filter { !duplicatedByUpstream.contains($0.id) }
    }

    /// Fork entries to append to upstream's palette item list.
    static var items: [QuickFileSwitcherPanel.Item] {
        bridgedCommands.map { command in
            QuickFileSwitcherPanel.Item(
                id: idPrefix + command.id,
                title: command.title,
                subtitle: command.category,
                isPinned: false,
                canTogglePin: false
            )
        }
    }

    /// Handle a palette selection. Returns false when the id is not fork-owned, so upstream's
    /// switch can fall through to its own `default:` behavior.
    ///
    /// `windowNumber` must be the editor's host window, passed in by the caller. Reading
    /// `NSApp.keyWindow` here would return the palette SHEET (it is key while you pick), whose
    /// number never matches `forkMatchesWindow`, so every command would be silently dropped.
    @discardableResult
    static func post(_ commandID: String, windowNumber: Int?) -> Bool {
        guard commandID.hasPrefix(idPrefix) else { return false }
        let registryID = String(commandID.dropFirst(idPrefix.count))
        guard let command = bridgedCommands.first(where: { $0.id == registryID }) else { return false }

        var userInfo: [AnyHashable: Any] = [:]
        if let windowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = windowNumber
        }
        NotificationCenter.default.post(
            name: command.notification,
            object: command.object,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
        return true
    }
}
