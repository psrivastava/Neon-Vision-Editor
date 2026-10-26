//
//  OpenLocation.swift
//  Neon Vision Editor — FORK ADDITION
//
//  Handles the `neonvisioneditor://goto?file=<abs>&line=N&column=N` URL emitted by the `nve`
//  CLI helper (task 4: CLI line:column invocation). Parses the request, ensures the file is open,
//  then routes to the existing `.moveCursorToLine` cursor-placement path.
//
//  macOS-only: the CLI helper and URL scheme are macOS features.
//

#if os(macOS)
import AppKit
import Foundation

enum ForkOpenLocation {

    /// Parsed goto request. Column is currently advisory — NVE's cursor-placement path is line-based,
    /// so we place the caret at the line start; column is retained for future column-precise support.
    struct Request: Sendable {
        let fileURL: URL
        let line: Int
        let column: Int
    }

    /// Returns a parsed request if `url` is a fork `goto` URL, else nil (so other schemes pass through).
    static func parse(_ url: URL) -> Request? {
        guard url.scheme == "neonvisioneditor", url.host == "goto",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        guard let filePath = value("file"), !filePath.isEmpty else { return nil }
        guard let line = Int(value("line") ?? ""), line > 0 else { return nil }
        let column = max(1, Int(value("column") ?? "1") ?? 1)
        let fileURL = URL(fileURLWithPath: filePath)
        return Request(fileURL: fileURL, line: line, column: column)
    }

    /// Handle a goto request: focus/open the file, then place the cursor. Returns true if handled.
    @MainActor
    static func handle(_ request: Request) -> Bool {
        let fileURL = request.fileURL.standardizedFileURL

        // Focus the file if already open; otherwise open it in the active/most-recent window.
        var targetWindowNumber: Int?
        if let existing = WindowViewModelRegistry.shared.viewModel(containing: fileURL) {
            _ = existing.viewModel.focusTabIfOpen(for: fileURL)
            targetWindowNumber = existing.windowNumber
            if let window = NSApp.window(withWindowNumber: existing.windowNumber) {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else if let target = WindowViewModelRegistry.shared.activeViewModel() {
            _ = target.openFile(url: fileURL)
        } else {
            return false
        }

        // Post cursor placement after a short delay so document load/highlight settles first,
        // matching how Go-to-Line and symbol navigation dispatch.
        var userInfo: [String: Any] = [:]
        if let targetWindowNumber {
            userInfo[EditorCommandUserInfo.windowNumber] = targetWindowNumber
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(
                name: .moveCursorToLine,
                object: request.line,
                userInfo: userInfo.isEmpty ? nil : userInfo
            )
        }
        return true
    }
}
#endif
