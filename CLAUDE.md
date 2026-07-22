# CLAUDE.md

Guidance for AI coding agents working in **Neon Vision Editor**. Read this first, then
[`ARCHITECTURE.md`](ARCHITECTURE.md) for subsystem boundaries and [`DEVELOPER.md`](DEVELOPER.md)
for code-level conventions.

## What this project is

A native **Swift 6** editor for **macOS 15+, iOS/iPadOS 18.6+, and visionOS 26.5+**. Editor-first
and minimal: fast file access, lightweight project navigation, native text editing, regex syntax
highlighting, markdown preview, macOS Git/terminal helpers, and optional AI completion. Ships via
GitHub Releases (notarized + Sparkle), the App Store, and TestFlight. Currently **v0.9.3**,
Apache-2.0, repo `h3pdesign/Neon-Vision-Editor`.

**In scope:** speed, readable UI, reliable highlighting, stability. **Out of scope (non-goals):**
plugin system, full IDE features (LSP, refactors, debugger). Keep PRs small and focused; see
[`CONTRIBUTING.md`](CONTRIBUTING.md).

## Repository layout

- `Neon Vision Editor/` — the app source (see `DEVELOPER.md` for the folder-by-folder map).
- `Neon Vision Editor App Clip/`, `Neon Vision Editor Share Extension/` — auxiliary targets.
- `Neon Vision EditorTests/` — XCTest target (~22 files).
- `Neon Vision Editor.xcodeproj/` — the build project (no SwiftPM manifest at root).
- `scripts/`, `scripts/ci/` — release, notarization, and verification tooling.
- Top-level `*.md` — README, ARCHITECTURE, CHANGELOG, SECURITY, PRIVACY, this file, DEVELOPER.

## Build & verify

There is **no `Package.swift`**; build through the Xcode project.

```bash
# Single-platform build
xcodebuild -project "Neon Vision Editor.xcodeproj" -scheme "Neon Vision Editor" \
  -destination 'platform=macOS,name=My Mac' build

# Preferred cross-platform check before finishing shared/UI changes
scripts/ci/build_platform_matrix.sh      # macOS + iOS Sim + iPad Sim, signing off
```

The matrix script serializes builds behind a lock and cleans `.DerivedDataMatrix/` on exit. **Always
remove any `.DerivedData*` folders you create during manual verification before finishing.**

Run tests via the `Neon Vision Editor` scheme in Xcode or `xcodebuild test`.

## Hard rules for changes

1. **Platform guards are mandatory.** AppKit code lives behind `#if os(macOS)`; UIKit behind
   `#if os(iOS) || os(visionOS)` (or `canImport(UIKit)`). Git and the integrated terminal are
   **macOS-only**. Shared models/services in `Core/`, `Data/`, `Models/` must stay platform-neutral
   and buildable for iPhone **and** iPad (`TARGETED_DEVICE_FAMILY = 1,2`).
2. **Never block the main actor** with file IO, process execution, diff building, PDF rendering, or
   large parsing. Offload with `Task.detached` / actors; hop back with `MainActor.run` only for UI.
3. **Swift 6 strict concurrency is on.** New cross-isolation data must be `Sendable`. Prefer actors
   over ad-hoc locks; use the existing `NVELock` wrapper only where an actor doesn't fit.
4. **Secrets go in Keychain**, never `UserDefaults`. AI provider tokens use `SecureTokenStore`.
5. **No telemetry, no logging of document content, prompts, tokens, or sensitive paths.** See
   `PRIVACY.md` and `SECURITY.md`. AI requests send only cursor/selection context over HTTPS.
6. **Respect the settings-default contract.** All user prefs are `@AppStorage("SettingsX")` keys
   with defaults registered centrally in `NeonVisionEditorApp`. Add new keys there too.
7. **A commit that touches source auto-bumps the build number** via the `.githooks/pre-commit`
   hook (docs-only commits are exempt). Install hooks once with `scripts/install_git_hooks.sh`.

## Where things live (quick index)

- App entry / scenes / menus → `App/NeonVisionEditorApp.swift`, `App/AppMenus.swift`
- Central editing model → `Data/EditorViewModel.swift`
- Editor text views → `UI/EditorTextView+macOS.swift`, `UI/EditorTextView+iOS.swift`
- Syntax highlighting (regex) → `Core/SyntaxHighlighting.swift`, `Core/LanguageDetector.swift`
- Markdown preview → `UI/MarkdownPreviewWebView.swift`, `UI/ContentView+MarkdownPreview*.swift`
- Git (macOS) → `Core/GitService.swift`, `Data/GitViewModel.swift`
- AI → `AI/AIClient.swift`, `Models/AIModel.swift`, `Core/AppleFMHelper.swift`, `Core/CompletionHeuristics.swift`
- Settings → `UI/NeonSettingsView.swift`

## Conventions

- Match the surrounding code: `ContentView` is intentionally split into many `ContentView+*.swift`
  extension files by concern — add new behavior to the right extension, don't grow the base file.
- Prefer `let`, value types, and early returns. Keep functions small.
- Localized strings exist for `en`, `de`, `zh-Hans` — keep user-facing text localizable.
- After UI changes, verify VoiceOver labels, keyboard navigation, focus escape from overlays, and
  compact-iPhone / regular-iPad layouts (see `ARCHITECTURE.md` → Testing and Verification).
- `AGENTS.md` / `PROJECT.md` are git-ignored; this `CLAUDE.md` and `DEVELOPER.md` are tracked.
