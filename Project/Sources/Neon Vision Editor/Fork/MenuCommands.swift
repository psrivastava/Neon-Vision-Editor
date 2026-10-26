//
//  MenuCommands.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Menu commands for fork-added editor features. Posts fork notifications observed by
//  ContentView+ForkCommands. Kept in a fork file; AppMenus.swift needs only a one-line hook.
//

import SwiftUI
#if os(macOS)
import AppKit

/// A "Fork Tools" command menu grouping string transforms, markup formatting, and rich copy.
/// Routed to the active window through the same `windowNumber` userInfo the upstream commands use.
struct ForkMenuCommands: Commands {

    var body: some Commands {
        // Command palette lives in the Editor-adjacent command space; Cmd+Shift+P (distinct from
        // Cmd+P Quick Open). Placed before Search so it is easy to find.
        CommandGroup(after: .textEditing) {
            Button("Command Palette…") { post(.forkShowCommandPaletteRequested) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Transform") {
            transformMenu(for: .caseConversion)
            transformMenu(for: .encoding)
            transformMenu(for: .lines)
            transformMenu(for: .numbers)

            Divider()

            Button("Format Markup (XML/HTML)") { post(.forkFormatMarkupRequested) }
            Button("Minify Markup (XML/HTML)") { post(.forkMinifyMarkupRequested) }

            Menu("Convert Line Endings") {
                Button("LF (Unix)") { post(.forkConvertLineEndingsRequested, object: ForkLineEnding.lf.rawValue) }
                Button("CRLF (Windows)") { post(.forkConvertLineEndingsRequested, object: ForkLineEnding.crlf.rawValue) }
                Button("CR (Classic Mac)") { post(.forkConvertLineEndingsRequested, object: ForkLineEnding.cr.rawValue) }
            }

            Divider()

            Button("Copy as HTML / Rich Text") { post(.forkCopyAsRichTextRequested) }
                .keyboardShortcut("c", modifiers: [.command, .option, .shift])
        }
    }

    @ViewBuilder
    private func transformMenu(for group: ForkStringTransform.Group) -> some View {
        Menu(group.rawValue) {
            ForEach(ForkStringTransform.allCases.filter { $0.group == group }, id: \.self) { transform in
                Button(transform.title) {
                    post(.forkApplyStringTransformRequested, object: transform.rawValue)
                }
            }
        }
    }

    private func post(_ name: Notification.Name, object: Any? = nil) {
        var userInfo: [AnyHashable: Any] = [:]
        if let windowNumber = NSApp.keyWindow?.windowNumber ?? NSApp.mainWindow?.windowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = windowNumber
        }
        NotificationCenter.default.post(
            name: name,
            object: object,
            userInfo: userInfo.isEmpty ? nil : userInfo
        )
    }
}
#endif
