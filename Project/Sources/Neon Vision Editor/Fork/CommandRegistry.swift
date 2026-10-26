//
//  CommandRegistry.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Declarative catalog of commands shown in the fork command palette (Cmd+Shift+P, task 5).
//  Kept distinct from Quick Open (Cmd+P) which lists *files*; this lists *actions*.
//  Each entry posts an existing notification, so the palette adds no new behavior of its own.
//

import Foundation

/// A single palette command: a title, an optional category for grouping, and the notification it posts.
public struct ForkCommand: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let notification: Notification.Name
    /// Optional object payload (e.g. a string-transform raw value).
    public let object: String?

    public init(id: String, title: String, category: String, notification: Notification.Name, object: String? = nil) {
        self.id = id
        self.title = title
        self.category = category
        self.notification = notification
        self.object = object
    }
}

public enum ForkCommandRegistry {

    /// All palette commands. Built from existing notifications (upstream + fork) so the palette is a
    /// pure launcher. Ordered by category; the palette applies fuzzy filtering on top.
    public static func allCommands() -> [ForkCommand] {
        var commands: [ForkCommand] = []

        // Navigation / find (existing upstream notifications).
        commands.append(ForkCommand(id: "quickOpen", title: "Quick Open File…", category: "Navigation", notification: .showQuickSwitcherRequested))
        commands.append(ForkCommand(id: "goToLine", title: "Go to Line…", category: "Navigation", notification: .showGoToLineRequested))
        commands.append(ForkCommand(id: "goToSymbol", title: "Go to Symbol…", category: "Navigation", notification: .showGoToSymbolRequested))
        commands.append(ForkCommand(id: "findInFiles", title: "Find in Files…", category: "Find", notification: .showFindInFilesRequested))
        commands.append(ForkCommand(id: "findReplace", title: "Find / Replace…", category: "Find", notification: .showFindReplaceRequested))

        // View (existing upstream notifications).
        commands.append(ForkCommand(id: "toggleMinimap", title: "Toggle Code Minimap", category: "View", notification: .toggleCodeMinimapRequested))
        commands.append(ForkCommand(id: "toggleSidebar", title: "Toggle Sidebar", category: "View", notification: .toggleSidebarRequested))
        commands.append(ForkCommand(id: "toggleProjectSidebar", title: "Toggle Project Structure Sidebar", category: "View", notification: .toggleProjectStructureSidebarRequested))

        // Fork: markup formatting + rich copy.
        commands.append(ForkCommand(id: "formatMarkup", title: "Format Markup (XML/HTML)", category: "Format", notification: .forkFormatMarkupRequested))
        commands.append(ForkCommand(id: "minifyMarkup", title: "Minify Markup (XML/HTML)", category: "Format", notification: .forkMinifyMarkupRequested))
        commands.append(ForkCommand(id: "formatJSON", title: "Format JSON", category: "Format", notification: .formatJSONDocumentRequested))
        commands.append(ForkCommand(id: "copyRich", title: "Copy as HTML / Rich Text", category: "Edit", notification: .forkCopyAsRichTextRequested))

        // Fork: line-ending conversion (task 7).
        commands.append(ForkCommand(id: "eolLF", title: "Convert Line Endings to LF (Unix)", category: "Line Endings", notification: .forkConvertLineEndingsRequested, object: ForkLineEnding.lf.rawValue))
        commands.append(ForkCommand(id: "eolCRLF", title: "Convert Line Endings to CRLF (Windows)", category: "Line Endings", notification: .forkConvertLineEndingsRequested, object: ForkLineEnding.crlf.rawValue))
        commands.append(ForkCommand(id: "eolCR", title: "Convert Line Endings to CR (Classic Mac)", category: "Line Endings", notification: .forkConvertLineEndingsRequested, object: ForkLineEnding.cr.rawValue))

        // Fork: string transforms (each transform becomes a command).
        for transform in ForkStringTransform.allCases {
            commands.append(ForkCommand(
                id: "transform.\(transform.rawValue)",
                title: "Transform: \(transform.title)",
                category: transform.group.rawValue,
                notification: .forkApplyStringTransformRequested,
                object: transform.rawValue
            ))
        }

        return commands
    }

    /// Case-insensitive subsequence fuzzy match (same feel as Quick Open). Empty query matches all.
    public static func filter(_ commands: [ForkCommand], query: String) -> [ForkCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return commands }
        return commands.filter { fuzzyMatches(title: $0.title.lowercased(), query: trimmed) }
    }

    /// True if every character of `query` appears in `title` in order.
    static func fuzzyMatches(title: String, query: String) -> Bool {
        var titleIndex = title.startIndex
        for queryChar in query {
            guard let found = title[titleIndex...].firstIndex(of: queryChar) else { return false }
            titleIndex = title.index(after: found)
        }
        return true
    }
}
