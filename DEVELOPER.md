# Neon Vision Editor — Developer Guide

Code-level companion to [`ARCHITECTURE.md`](ARCHITECTURE.md). Architecture describes *what the
subsystems are and where their boundaries sit*; this document describes *how the code is actually
organized, the patterns you must follow, and the non-obvious mechanics* you need before editing.

Last verified against **v0.9.3** (`MARKETING_VERSION = 0.9.3`, build `841`).

---

## 1. Build system & targets

There is **no `Package.swift`** — the source of truth is `Neon Vision Editor.xcodeproj`. Key build
settings (from `project.pbxproj`):

| Setting | Value |
|---|---|
| `SWIFT_VERSION` | `6.0` (strict concurrency) |
| `MACOSX_DEPLOYMENT_TARGET` | `15.0` (some aux targets `14.6`) |
| `IPHONEOS_DEPLOYMENT_TARGET` | `18.6` |
| `XROS_DEPLOYMENT_TARGET` | `26.5` |
| `TARGETED_DEVICE_FAMILY` | `1,2` (iPhone+iPad); `1,2,7` where visionOS applies |
| `PRODUCT_BUNDLE_IDENTIFIER` | `h3p.Neon-Vision-Editor` (+ `.Clip`, `.ShareExtension`, `Tests`) |

**Targets:** main app, **App Clip** (`Neon Vision Editor App Clip/AppClipApp.swift`), **Share
Extension** (`.../ShareViewController.swift`), and the XCTest bundle.

**Schemes:** `Neon Vision Editor` (dev), `Neon Vision Editor AppStore` (release/App Store),
`Neon Vision Editor App Clip`.

**Single external dependency:** [Sparkle](https://github.com/sparkle-project/Sparkle) `>= 2.9.0`,
linked **macOS-only** via a `platformFilters = (macos)` build file. Everything else is
Apple-frameworks only (`SwiftUI`, `AppKit`, `UIKit`, `WebKit`, `FoundationModels`, `StoreKit`).

### Build number auto-bump

`.githooks/pre-commit` runs `scripts/bump_build_number.sh` on any non-docs commit and re-stages
`project.pbxproj`. Docs-only commits (`README.md`, `CHANGELOG.md`, `docs/*`, `.github/*`,
`scripts/*`, `.githooks/*`) are skipped. Set `NVE_SKIP_BUILD_NUMBER_BUMP=1` to bypass. Enable with
`scripts/install_git_hooks.sh` (sets `core.hooksPath = .githooks`).

---

## 2. Source tree (folder by folder)

Under `Neon Vision Editor/`:

| Dir | LoC (~) | Contents |
|---|---|---|
| `App/` | 1.5k | `NeonVisionEditorApp.swift` (`@main`, scenes, default settings, runtime language override), `AppMenus.swift` (macOS menu commands). |
| `Core/` | 8.2k | Platform-neutral services: syntax, language detection, completion heuristics, project index, diff, Git service (macOS), remote sessions, updates, recent files, runtime policy/reliability, `NVELock`. |
| `UI/` | 44k | All SwiftUI/AppKit/UIKit views. Dominated by `ContentView` and its `ContentView+*.swift` extensions, `NeonSettingsView`, editor text-view representables, sidebar, previews. |
| `Data/` | 3.1k | `EditorViewModel` (central model), `GitViewModel`, `SecureTokenStore` (Keychain), `SupportPurchaseManager` (StoreKit). |
| `Models/` | ~34 | `AIModel.swift` (provider/model enum). |
| `AI/` | 0.5k | `AIClient.swift` — the `AIClient` protocol + per-provider implementations. |
| `Resources/` | — | `Assets.xcassets`, `AppIcon.icon`, `PrivacyInfo.xcprivacy`, bundled `nve` helper. |
| `*.lproj` | — | Localizations: `en`, `de`, `zh-Hans`. |

**Largest files (edit with care, they are split by design):** `NeonSettingsView.swift` (6.3k),
`ContentView.swift` (4.2k), `PanelsAndHelpers.swift` (4.0k),
`ContentView+MarkdownPreviewExport.swift` (3.0k), `EditorTextView+iOS.swift` (2.8k),
`EditorViewModel.swift` (2.4k).

### The `ContentView+*` extension pattern

`ContentView` (a single `struct ContentView: View`) is deliberately spread across ~20 extension
files, each owning one concern: `+Toolbar`, `+Actions`, `+QuickSwitcherFind`, `+AICompletion`,
`+MarkdownPreviewUI`, `+MarkdownPreviewExport`, `+MarkdownFormatting`, `+SessionPersistence`,
`+ProjectSidebar`, `+PreviewSplit`, `+StartupOverlay`, `+TabChromeStatus`, `+StructuredData`,
`+SVGPreviewUI`, `+LanguageSupport`, `+Types`, etc. **Add new `ContentView` behavior to the
matching extension file** (or a new one) rather than growing `ContentView.swift`. Nested enums that
model view state (`PreviewMode`, `PerformancePreset`, `DelimitedViewMode`, `PlistViewMode`,
`CrashReportViewMode`) live on `ContentView` in the base file.

---

## 3. State model & observation

The app is **mid-migration**: newer models use the **Observation framework** (`@Observable`), while
three legacy managers still use Combine `ObservableObject`. They inject through **different** SwiftUI
mechanisms — know which is which before wiring a view:

| Model | Macro | Ownership / Injection |
|---|---|---|
| `EditorViewModel` (`Data/EditorViewModel.swift:562`) | `@MainActor @Observable` | `@State` at App level → `.environment(...)` → `@Environment(EditorViewModel.self)` |
| `TabData` (`Data/EditorViewModel.swift:436`) | `@Observable` | held by `EditorViewModel` (backs `PieceTableDocument`) |
| `GitViewModel` (`Data/GitViewModel.swift:6`) | `@MainActor @Observable` | **not global** — `@State` in `ContentView:419`, passed down |
| `AIActivityLog` (`Core/AIActivityLog.swift:4`) | `@MainActor @Observable` | debugging surface |
| `RemoteSessionStore` (`Core/RemoteSessionStore.swift:113`) | `@Observable` | remote-session state |
| `SupportPurchaseManager` (`Data/SupportPurchaseManager.swift:8`) | `ObservableObject` | `@StateObject` → `.environmentObject` → `@EnvironmentObject` |
| `AppUpdateManager` (`Core/AppUpdateManager.swift:45`) | `ObservableObject` | `@StateObject` → `@EnvironmentObject` |
| `IntegratedTerminalSession` (`UI/IntegratedTerminalContent.swift:8`) | `ObservableObject` | `@StateObject` in `SidebarViews.swift:924` |

So in `ContentView` you'll see a mix: `@Environment(EditorViewModel.self) var viewModel` alongside
`@EnvironmentObject private var supportPurchaseManager`. Match the style of whichever model you
touch. `@Published` (23 sites) is confined to the three `ObservableObject` managers. Custom
environment keys also exist (e.g. `\.showGrokError`, `\.grokErrorMessage`).

`EditorViewModel` is the hub: tabs, file load/save, language selection, dirty tracking, remote
documents, document snapshots, and large-file safeguards. It hosts several `Sendable` value structs
for cross-actor payloads (`ExternalFileConflictState`, `RemoteSaveIssueState`,
`DocumentComparisonSnapshot`, `RestoredTabSnapshot`, …) and a private `actor TabCommandQueue`
serializing tab mutations.

### PieceTableDocument

Large-document text storage uses a `PieceTableDocument` (`EditorViewModel.swift:265`) — a piece-table
buffer (original + add sources, list of `Piece`s) rather than a monolithic `String`. This is the
backing store that keeps edits and large-file handling cheap. Treat it as the canonical document
representation when working on load/save/mutation paths.

---

## 4. Notification-driven decoupling

The codebase leans heavily on `NotificationCenter` to decouple menu commands, the editor
representables, and `ContentView` (a common pattern when bridging AppKit/UIKit `NSViewRepresentable`
back to SwiftUI). There are **~54** custom `Notification.Name`s across the app, defined in several
`extension Notification.Name` blocks (e.g. `UI/EditorTextView.swift:358`,
`UI/PanelsAndHelpers.swift:3702`, `UI/EditorTextView+RuntimePolicy.swift:8`).

The **central catalog (~48 names)** is `UI/PanelsAndHelpers.swift:3702` — command-style requests like
`.clearEditorRequested`, `.showFindReplaceRequested`, `.showQuickSwitcherRequested`,
`.openProjectFolderRequested`, `.selectAIModelRequested`, `.moveCursorToLine`, `.moveCursorToRange`
(`nonisolated`), `.caretPositionDidChange`, `.droppedFileURL`, `.recentFilesDidChange`,
`.sharedImportsDidChange`, `.editorViewportDidChange`, `.showUpdaterRequested`. Editor-text events
live in `UI/EditorTextView.swift:358` (`pastedFileURL`, `editorSelectionDidChange`,
`editorFocusDidChange`, `markdownFormattingRequested`, …).

**Flow:** posts (~68 sites) originate mostly from the AppKit/UIKit representable bridges and menu
commands; observation is centralized in the SwiftUI layer via a long chain of
`.onReceive(NotificationCenter.default.publisher(for:))` handlers in `ContentView.swift` (~1077+).
This is how the `NSViewRepresentable`/`UIViewRepresentable` bridges signal up to SwiftUI without
bindings.

**Convention:** define a name in the `extension Notification.Name` block nearest the subsystem that
owns it, post from the AppKit/UIKit side or a menu command, observe in the relevant `ContentView+*`
extension. Prefer this over threading closures through many view layers.

**Separate cross-process channel:** the Share Extension → app handoff uses **Darwin notifications**
(`CFNotificationCenterGetDarwinNotifyCenter`) in `Core/SharedImportNotificationBridge.swift`, not the
in-process `NotificationCenter`. Related: `SharedImportStore.swift`, `ShareImportHandoff.swift`.
Appearance/theme iCloud changes are observed via `NSUbiquitousKeyValueStore.didChangeExternallyNotification`.

---

## 5. Concurrency (Swift 6 strict)

Strict concurrency is fully enabled; the codebase reflects it heavily:

- **~122** `@MainActor` annotations, **~289** `nonisolated`, **~102** `Task {`, **~26**
  `Task.detached`, **~22** `MainActor.run`, **7** `actor` declarations, **10** `@unchecked Sendable`.
- UI models are `@MainActor`. Heavy work (file IO, diff, indexing, PDF, process exec) runs on
  `Task.detached` or dedicated actors, then hops back via `MainActor.run` for UI updates.
- `Core/GitService.swift` is a **macOS-only actor** that shells out to `git`.
- `EditorViewModel.TabCommandQueue` is an actor serializing tab operations.

### NVELock

`Core/NVELock.swift` is a hand-rolled, `@unchecked Sendable` lock wrapper (`NSLock` + a raw-pointer
value box) "compatible with the macOS 14 deployment target." Use it for the narrow cases where an
actor is overkill or would introduce await-hops in synchronous init/callback paths (e.g. the runtime
language `Bundle` override in `App/NeonVisionEditorApp.swift`, session-restoration callbacks). For
ordinary shared mutable state, **prefer an actor**.

---

## 6. Platform abstraction

The macOS/iOS split is explicit and file-level where it matters:

- Editor: shared helpers in `UI/EditorTextView.swift`; macOS `NSTextView` wrapper in
  `EditorTextView+macOS.swift` (+`+macOSTextView.swift`); iOS/iPadOS `UITextView` wrapper in
  `EditorTextView+iOS.swift`. Line numbers: macOS `LineNumberRulerView`; iOS uses lightweight
  overlay views.
- macOS-only subsystems: Git (`GitService`/`GitViewModel`/`SidebarViews+GitTab`), the integrated
  terminal (`IntegratedTerminalContent.swift`, `PanelsAndHelpers.swift`), Sparkle
  (`SparkleUpdateController.swift`), the `nve` CLI helper.
- Guard idioms: `#if os(macOS)` for AppKit, `#if os(iOS) || os(visionOS)` for UIKit,
  `#if canImport(FoundationModels)` for on-device AI. `AppUpdateManager` keeps a non-macOS branch so
  the updater still compiles where Sparkle is absent.

Anything in `Core/`, `Data/`, `Models/` must compile for all platforms — no bare AppKit/UIKit
imports without a guard.

---

## 7. Settings & persistence

- **~113 distinct `"SettingsX"` keys**, referenced through **~221** `@AppStorage` sites. Defaults are
  registered centrally in `NeonVisionEditorApp` (search `register(defaults:)` /
  `"SettingsShowLineNumbers": true` etc. around `App/NeonVisionEditorApp.swift:420`). **New prefs:
  add the `@AppStorage` and register its default there.**
- Sensitive data → **Keychain** via `Data/SecureTokenStore.swift` (`enum SecureTokenStore`): service
  `"h3p.Neon-Vision-Editor.tokens"`, `kSecClassGenericPassword`,
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, keyed by `enum APITokenKey` (grok, openAI, gemini,
  anthropic, openCodeGo, customProvider). It also runs `migrateLegacyUserDefaultsTokens()` to pull any
  tokens that once lived in `UserDefaults` into the Keychain. Never store secrets in `UserDefaults`.
- Appearance/theme prefs get **opt-in iCloud KVS sync** via `Core/AppearanceThemeCloudSync.swift`
  (appearance/theme only — not documents or tokens).
- Session/tab restoration lives in `ContentView+SessionPersistence.swift` with `Codable`
  `SavedDraftSnapshot` / `SavedDraftTabSnapshot` types.
- `Core/RecentFilesStore.swift`, `Core/ShortcutPreferences.swift` hold their own persisted state.

---

## 8. Syntax highlighting internals

`Core/SyntaxHighlighting.swift` is **regex-based** (no TreeSitter). Notable pieces:

- `SyntaxRegexCache` (`:8`) — a private cache so compiled `NSRegularExpression`s are reused (regex
  compilation is the expensive part; never compile in a hot path).
- `SyntaxColors` (`Sendable`), `SyntaxPatternProfile` (`Sendable, Equatable`),
  `SyntaxEmphasisPatterns` — the language/theme model.
- Bracket-scope matching (`BracketScopeMatch`) and indentation-scope matching
  (`IndentationScopeMatch`, for Python/YAML-style) in `UI/EditorTextView.swift`.
- Highlighting is **throttled and bounded for large files**, with fast-path scanners for
  JSON/markdown-like content.

`Core/LanguageDetector.swift` maps extensions + content heuristics to language IDs.
Because tests compile some `Core` files directly, **keep reusable core files test-target-safe** —
don't add app-only or UI dependencies to them.

---

## 9. AI subsystem

Layered and provider-pluggable:

- `AI/AIClient.swift` — `protocol AIClient { func streamSuggestions(prompt:) -> AsyncStream<String> }`
  (streaming is the only interface) with concrete clients: `AppleIntelligenceAIClient`,
  `OpenAIAIClient`, `GeminiAIClient`, `AnthropicAIClient`, `GrokAIClientStreaming`, and
  `OpenAICompatibleAIClient` (reused for OpenCode Go and custom providers). Config: `OpenCodeGoConfig`,
  `CustomProviderConfig`. Security helpers (`nonisolated`): `isSecureOpenAICompatibleBaseURL`,
  `isLoopbackOpenAICompatibleHost`.
- **`AIClientFactory.makeClient(for:...)`** (`AIClient.swift:456`) is the dispatcher: it takes an
  `AIModel` + closure-based token/model providers (wired to `SecureTokenStore` at the call site) and
  returns an `AIClient?`. **Every provider falls back to `AppleIntelligenceAIClient()` when its API
  key is missing/invalid** — Apple Intelligence is the universal fallback.
- `Models/AIModel.swift` — the canonical `enum AIModel: String, CaseIterable, Identifiable`
  (`appleIntelligence, grok, openAI, gemini, anthropic, openCodeGo, customProvider`).
- `Core/AppleFMHelper.swift` — `enum AppleFM` wrapping on-device **FoundationModels**
  (`appleFMHealthCheck` / `appleFMComplete` / `appleFMStream`), behind
  `#if canImport(FoundationModels)` with a stub fallback branch.
- `Core/CompletionHeuristics.swift` — local completion context, keyword fallback, document-word
  matching, and **sanitization of model suggestions** (never trust raw model output).
- `UI/ContentView+AICompletion.swift` — coordinates local vs provider-backed completion.
- `Core/AIActivityLog.swift` + `UI/AIActivityLogView.swift` — user-visible activity log.

**Privacy contract:** requests are HTTPS-only, send only cursor/selection context, and must not log
prompts/tokens/content. Tokens come from `SecureTokenStore`. Custom OpenAI-compatible endpoints must
be HTTPS.

---

## 10. Other subsystems (pointers)

- **Project index / search** — `Core/ProjectFileIndex.swift` (off-main, cancellation-checked,
  skips ignored folders), `Core/ProjectIgnoredFolders.swift` (`.git`, `.build`, `node_modules`,
  `DerivedData`). Find-in-Files prefers `rg` on macOS, else bounded Swift scan.
- **Diff/compare** — `Core/DocumentDiff.swift` (line-oriented hunks, build detached),
  `UI/DiffComparisonView.swift`, `UI/FolderCompareView.swift`.
- **Markdown preview/export** — `UI/MarkdownPreviewWebView.swift` (`WKWebView`),
  `ContentView+MarkdownPreview{UI,Export}.swift`, `UI/MarkdownPreviewPDFRenderer.swift`.
- **Updates** — `Core/AppUpdateManager.swift` (GitHub release checks) + `SparkleUpdateController`
  (macOS) + `UI/AppUpdaterDialog.swift`.
- **Remote sessions** — `Core/RemoteSessionStore.swift`; disabled by default
  (`SettingsRemoteSessionsEnabled`); must not log document contents/paths.
- **Reliability** — `Core/RuntimeReliabilityMonitor.swift` (launch-phase markers),
  `Core/ReleaseRuntimePolicy.swift`, `Core/EditorPerformanceMonitor.swift`.
- **Share import** — `Core/ShareImportHandoff.swift`, `SharedImportStore.swift`,
  `SharedImportNotificationBridge.swift` (bridges the Share Extension into the app).

---

## 11. Testing

XCTest target (`import XCTest`; 20+ files, no swift-testing yet). Tests focus on the pure/core logic
that is safe to compile directly:

`SyntaxHighlightingRegressionTests`, `MarkdownSyntaxHighlightingTests`, `LanguageDetectorTests`,
`DocumentDiffTests`, `CompletionHeuristicsTests`, `EditorViewModelFileOpenTests`,
`EditorViewModelTabTests`, `AIClientFactoryTests`, `AppUpdateManagerTests`,
`RecentFilesStoreTests`, `ShortcutPreferencesTests`, `ThemeSettingsTests`,
`ReleaseRuntimePolicyTests`, `ToolbarActionSelectionTests`, `WindowTranslucencyTests`,
`LineNumberRulerViewTests`, `MarkdownListReturnTests`, `MarkdownPreviewPDFRendererTests`,
`IntegratedTerminalSessionTests`, `EditorSettingsDefaultsTests`.

Note: the test target vendors copies of `LanguageDetector.swift` and `NVELock.swift` so those units
compile without pulling the whole app in — if you change those source files, keep the test copies in
sync (or verify the target membership).

**Verification workflow:** targeted tests for changed logic → `scripts/ci/build_platform_matrix.sh`
for shared/UI changes → clean up any `.DerivedData*`.

---

## 12. Scripts & release tooling

`scripts/` and `scripts/ci/` hold the release machinery. Highlights:

- `ci/build_platform_matrix.sh` — the canonical cross-platform build gate (lock-serialized, retries
  on transient build-system/`actool` errors, cleans derived data).
- `ci/release_gate.sh`, `ci/release_preflight.sh`, `ci/app_store_review_preflight.sh`,
  `ci/appclip_preflight.sh` — readiness checks.
- `ci/localization_audit.py`, `ci/markdown_preview_theme_audit.py`, `ci/privacy_log_audit.sh` —
  correctness/privacy audits.
- `release_prep.sh`, `release_all.sh`, `run_selfhosted_notarized_release.sh`,
  `archive_testflight.sh`, `bump_build_number.sh` — packaging/notarization/TestFlight.
- `create_homebrew_cask_pr.sh` / `create_homebrew_cask_handoff_issue.sh` — Homebrew Cask sync
  (recent commit history is dominated by this automation).
- `nve` — the macOS CLI helper (forwards `open`/`--line`/`--wait`/`--new-window` into the app via
  Launch Services; **reads no file contents**, requests **no** Full Disk / Accessibility / admin —
  see `docs/CommandLineHelper.md`).

Extra reference docs: `docs/XCODE_CLOUD_RELEASE.md`, `docs/notarized-github-runner-workflow.md`,
`docs/AppStoreReviewNotes.md`, and the `release/*` checklists.

---

## 13. Gotchas

- **`AIModel` looks defined twice but isn't.** The canonical enum is `Models/AIModel.swift`. The copy
  in `AI/AIClient.swift` is a non-compiling reference stub wrapped in `#if false` (with a comment
  pointing at the real definition). Don't remove the guard or "reconcile" the two — the stub is inert.
- **`AppleFM` appears twice** in `AppleFMHelper.swift` — a real implementation under
  `#if canImport(FoundationModels)` and a stub `enum AppleFM` for platforms without it. Edit the
  correct branch.
- **Git-ignored agent files:** `AGENTS.md`, `PROJECT.md`, `IDEA.md` are ignored (`.gitignore`).
  `CLAUDE.md` and this `DEVELOPER.md` are tracked.
- **Don't over-refactor `ContentView`.** Its size is intentional structure, not debt — the extension
  split is the module boundary.
- **macOS wrap/scroll rendering is fragile.** Recent releases (v0.9.1–v0.9.3) were largely TextKit
  viewport/width fixes (see `CHANGELOG.md`). When touching `EditorTextView+macOS*`, re-run the
  wrap/scroll regression tests and verify no stale source-pane width is retained after tab/sidebar/
  preview transitions.
