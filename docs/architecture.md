# Henge Architecture

Henge is a resident macOS 13+ menu-bar utility written in pure Swift with zero third-party dependencies. Its architecture enforces strict separation between platform-independent text-transformation rules and macOS system integrations (`AppKit`, `SwiftUI`, `ApplicationServices`, `Carbon`, and `ServiceManagement`).

## Layering & Domain Purity

```text
UI (SwiftUI / AppKit)
  ↓
Application (Coordinator & Use Cases)
  ↓
Domain (Pure Swift + Foundation)
  ↑
Infrastructure (macOS APIs & System Adapters)
```

- **`Sources/App/`** — Application entry point and composition root: `HengeMain` (`HengeApp.swift`, intercepts `--probe` before launching `HengeApp` and enforces `SingleInstanceGuard`), `SingleInstanceGuard` (`SingleInstanceGuard.swift`, exempts `--probe` runs and processes without a bundle identifier, activating an earlier peer instance if one is already running and exiting duplicates), `AppDelegate` (`AppDelegate.swift`, sets `.accessory` activation policy), `HengeApp` (`HengeApp.swift`, hosts `MenuBarExtra` with `MenuBarIconLabel` and coordinates `SettingsWindowController`, `OnboardingWindowController`, and `MenuBarLifecycleObserver`), and `AppEnvironment` (`AppEnvironment.swift`, wires live dependencies).
- **`Sources/UI/`** — SwiftUI and AppKit-hosted views:
  - `MenuBar/MenuBarView.swift` — `MenuBarView` popover (including one-click **Exclude \<App\>** for the frontmost external app) and `MenuBarLifecycleObserver`.
  - `MenuBar/MenuBarIcon.swift` — `MenuBarIcon` and `MenuBarIconLabel`, rendering state-aware template images and badges for `MenuBarIconState` (`.active`, `.disabled`, `.permissionRequired`, `.degraded`).
  - `Components/SingletonWindowController.swift` — `SingletonWindowController<Content: View>` managing singleton `NSWindow` + `NSHostingController` lifecycle, `.eventTracking` deferral, activation, and close hooks.
  - `Onboarding/OnboardingView.swift` — `OnboardingView` and `OnboardingWindowController` (backed by `SingletonWindowController`) for single-window first-launch onboarding and Accessibility permission polling (automatically stopped when the window closes).
  - `Settings/SettingsView.swift` — `SettingsView`, `ShortcutRecorder`, and `SettingsWindowController` (backed by `SingletonWindowController`).
  - UI views bind to `HengeCoordinator` and contain no business or Accessibility logic.
- **`Sources/Application/`** — Orchestration and state management: `HengeCoordinator` (`HengeCoordinator.swift`), `ApplicationState` (`ApplicationState.swift`, including `MenuBarIconState`), `FixTextUseCaseProtocol` / `LiveFixTextUseCase` (`FixTextUseCase.swift`, returning `FixOutcome`), `StatusPresenter` (`StatusPresenter.swift`, owning user-facing status text and menu-bar icon-state formatting), and `L10n` (`Localization.swift`, Foundation bundle localization helper).
- **`Sources/Domain/`** — Pure business logic with **zero** imports of `AppKit`, `SwiftUI`, `ApplicationServices`, `Carbon`, or `ServiceManagement` (only `Foundation`, or pure Swift):
  - `FixOutcome.swift` — `FixOutcome` and `FixFailureReason` structured pipeline outcomes.
  - `Layout/` — `Layout`, `LayoutDetecting` / `MajorityLayoutDetector`, `LayoutMapping`, `CasePreserving` / `DefaultCasePreserver`, `WordBoundaryDetecting` / `DefaultWordBoundaryDetector`, and `TextTransforming` / `SimpleTextTransformer`.
  - `Applications/` — `ApplicationIdentity`, `ExceptionMatcher`, and `ExceptionManager`.
  - `Hotkey/` — `Shortcut` (including optional physical `keyCode`) and `Shortcut.Modifiers`.
- **`Sources/Configuration/`** — Local persistence and schema migration: `AppConfiguration` (including `hasCompletedOnboarding`), `ConfigurationMigrator`, and `ConfigurationStore` (`JSONConfigurationStore` and `InMemoryConfigurationStore`).
- **`Sources/Infrastructure/`** — Protocol-backed macOS adapters:
  - `AppRuntime.swift` — Thin facade holding only `AppRuntime`, its default extension, and `LiveAppRuntime`, delegating to focused Accessibility, hotkey, permission, and application-activation services.
  - `Accessibility/AccessibilitySnapshots.swift` — Probe and write result/snapshot types (`FocusedElementProbe`, `FocusedElementProbeFailure`, `FocusedElementSnapshot`, `SelectionProbeFailure`, `SelectionSnapshot`, `TextContextProbe`, `SelectionRangeSnapshot`, `SelectionWriteResult`, `SelectionWriteFailure`, `ResolvedFocusedElement`).
  - `Accessibility/AccessibilityTextService.swift` — `AccessibilityTextService` (plus `AccessibilityElementAccessing` / `SystemAccessibilityElementAccessor`), handling focused-element resolution, context inspection (`inspectTextContext(in:)`), and unified replacement (`replaceText(_:range:context:expectedText:with:)`, trying direct AX first and falling back to `ClipboardReplacing` on `.unsupported`).
  - `Accessibility/PermissionProbe.swift` — `AccessibilityPermissionProbe` caching `AXIsProcessTrusted()` for a 1-second TTL (`defaultTimeToLive = 1.0`) to avoid repeated `tccd` IPC round trips, invalidated on permission prompts, opening System Settings, and app activation.
  - `Accessibility/TextTarget.swift` — `TextTarget` (holding `ApplicationIdentity`, `FocusedElementSnapshot`, and the opaque resolved `AXUIElement`) and `TextContext`.
  - `Applications/ActiveApplicationProvider.swift` — `ActiveApplicationProviding`, `WorkspaceActiveApplicationProvider`, `WorkspaceApplicationSource` (`SystemWorkspaceApplicationSource`), and `WorkspaceApplicationSnapshot`. `WorkspaceActiveApplicationProvider` owns the single `NSWorkspace.didActivateApplicationNotification` observer and exposes `setActivationHandler(_:)` so permission refreshes and target tracking funnel through one activation source.
  - `Applications/ApplicationActivator.swift` — `ActivationWaiter` (awaiting workspace activation notifications with non-finite guards and a 60-second ceiling via `sleepNanoseconds(for:)`) and `ApplicationActivator` (`prepareTargetApplicationForFixText(_:)`), restoring focus before menu-bar `Fix Text` execution without tight Accessibility polling.
  - `Hotkey/HotkeyRegistrar.swift` — `HotkeyRegistrar` and `HotkeyRegistrationError` wrapping Carbon `InstallEventHandler` and `RegisterEventHotKey`.
  - `Hotkey/KeyboardLabel.swift` — `CarbonHotkey` key-code/modifier mapping, extended keys (`Space`, `Return`, arrows, `F1`–`F12`), and `systemASCIICapableLabel(forKeyCode:)`.
  - `Hotkey/ShortcutCaptureEvaluator.swift` — `ShortcutCaptureEvaluator` and `ShortcutCaptureResult`, isolating key-capture validation and Escape/modifier handling from SwiftUI views.
  - `Layout/NativeKeyboardLayoutMapper.swift` — `NativeKeyboardLayoutMapper` implementing `LayoutMapping` via Carbon TIS and `UCKeyTranslate` with a bundled ANSI fallback table; `NativeKeyboardLayoutMapper.bundled()` provides the explicit headless/test fallback path (process-name sniffing removed).
  - `Clipboard/` — `ClipboardManaging`, `PasteboardBacking` (`SystemPasteboardBacking`), `AppKitClipboardManager`, `ClipboardSnapshot`, `ClipboardSizePolicy` (32 MiB / `33_554_432`-byte cap on non-exempt representations), `ClipboardReplacing`, `AppKitClipboardReplacement`, and `ClipboardReplacementResult` (`.success`, `.pasteUnverified`, `.restoreFailed`, `.superseded`, `.failed`).
  - `Diagnostics/Diagnostics.swift` — Typed `os.Logger` facade (`Diagnostics.logger(_:)`) under subsystem `io.github.413d.Henge`, organized by `DiagnosticsCategory` (`hotkey`, `text`, `clipboard`, `config`, `loginItem`) where `.clipboard` and `.config` emit structured failure events today while `.hotkey`, `.text`, and `.loginItem` categories are defined for future instrumentation, emitting static `DiagnosticsLabel` events, `DiagnosticsLengthBucket` sizes, and ASCII-validated bundle identifiers or UTI type names (`Diagnostics.bundleIdentifier(_:)`, `Diagnostics.pasteboardTypeNames(_:)`). Enforces Henge's strict privacy rule: no user text, passwords, or clipboard contents are ever logged.
  - `Lifecycle/` — `LoginItemManaging` (`LoginItemStatus` including `.requiresApproval`), `InMemoryLoginItemManager`, and `SMAppServiceLoginItemManager`.
  - `Probes/HengeProbeRunner.swift` — `HengeProbeRunner` diagnostic CLI harness.

## Text-Fixing Pipeline

When the user presses the global hotkey (default `⌥X`) or selects **Fix Text** in the menu bar, `HengeCoordinator` and `LiveFixTextUseCase` execute a strict guardrail-first pipeline:

```text
Hotkey / Menu Action
  → [1] Guardrails (Enabled, Excluded App, AX Permission, Secure Field)
  → [2] Target Text Resolution (Selection or Word Around Caret)
  → [3] Direction Detection & Character Mapping
  → [4] Replacement (Direct AX Primary → Clipboard Fallback + Restore)
```

### 1. Guardrails

1. **Enabled check** — `HengeCoordinator` unregisters the global hotkey while disabled and defines `canTriggerFixText` directly as `state.configuration.isEnabled`. The app stays resident in the menu bar without acting on keystrokes.
2. **Excluded applications** — `ExceptionMatcher` checks the active application's bundle identifier (resolved by `WorkspaceActiveApplicationProvider`) against `AppConfiguration.excludedApplicationBundleIdentifiers`. Both `HengeCoordinator` and `LiveFixTextUseCase.execute(...)` abort immediately for excluded apps.
3. **Accessibility permission** — `LiveAppRuntime.hasAccessibilityPermission` queries `AccessibilityPermissionProbe.isTrusted()` (cached for ≤1 s TTL and invalidated on permission prompts, opening System Settings, and app activation). Missing permission halts execution safely and updates the UI status via `FixOutcome.failed(.missingPermission)`.
4. **Secure-field guard** — `AccessibilityTextService.resolveFocusedElement()` inspects `kAXRoleAttribute` and `kAXSubroleAttribute`. If either equals `"AXSecureTextField"`, `FocusedElementSnapshot.isSecure` is `true`. Both `HengeCoordinator` and every inspection and write entry point on `AccessibilityTextService` (`inspectTextContext(in:)`, `replaceText(_:range:context:expectedText:with:)`) refuse to read, copy, transform, or replace content in secure fields.

### 2. Target Text Resolution

`AccessibilityTextService.inspectTextContext(in:)` resolves the focused `AXUIElement` once per fix operation, returning a `TextContext` containing an opaque `TextTarget` (embedding the resolved element alongside `ApplicationIdentity` and `FocusedElementSnapshot`) and a `SelectionSnapshot`:

- **Active selection first** — If `kAXSelectedTextRangeAttribute` has `length > 0`, `kAXSelectedTextAttribute` is read and transformed directly.
- **Word around caret** — If no text is selected (`isCaretContext == true`), `LiveFixTextUseCase` converts the caret UTF-16 offset using `String.Index` without materializing full-document arrays, then delegates to `DefaultWordBoundaryDetector` (`WordBoundaryDetecting`) to locate the contiguous word around (or immediately adjacent to) the caret. `DefaultWordBoundaryDetector` scans a ±256-character delimiter window (`windowSize = 256`) around the caret for responsiveness on large documents, while continuing past the window inside word-character runs (letters, decimal digits, and `_`) so words themselves are never truncated.

### 3. Layout Direction Detection & Character Mapping

- **Direction from text, not input source** — `MajorityLayoutDetector` (`LayoutDetecting`) counts English (Basic Latin) vs. Russian (Cyrillic) letters in the target text. Ties or neutral text (digits/punctuation only) produce `.noOp(.ambiguousDirection)` or `.noOp(.neutralText)`, which `LiveFixTextUseCase` reports as `FixOutcome.nothingToFix`.
- **Physical key mapping** — `NativeKeyboardLayoutMapper` queries Carbon TIS (`com.apple.keylayout.US` and `com.apple.keylayout.Russian` / `com.apple.keylayout.RussianWin`) and `UCKeyTranslate` in its production initializer, falling back to a bundled ANSI table when system layout data is unavailable; `NativeKeyboardLayoutMapper.bundled()` provides the explicit headless/test path.
- **Formatting preservation** — `SimpleTextTransformer` combines `NativeKeyboardLayoutMapper` with `DefaultCasePreserver` (`CasePreserving`) to preserve uppercase/lowercase casing, digits, whitespace, `_`, and trailing delimiter punctuation.

### 4. Replacement (Accessibility Primary, Clipboard Fallback)

1. **Direct Accessibility replacement (primary)** — `LiveFixTextUseCase` passes the resolved `TextTarget` to `AccessibilityTextService.replaceText(_:range:context:expectedText:with:)`, which reuses the embedded `AXUIElement` after checking element identity/focus (`isFocusedElement(_:in:)` via `CFEqual`) at entry and context freshness (`isCurrentTextContext(...)`) before writing. It updates `kAXSelectedTextRangeAttribute` if expanding a caret word, writes `kAXSelectedTextAttribute` via `AXUIElementSetAttributeValue`, moves the caret to the end of the replaced text, and returns `.success(viaClipboard: false)`.
2. **Clipboard copy/paste fallback** — Only when direct Accessibility replacement returns `.unavailable(.unsupported)` does `AccessibilityTextService.replaceText(_:range:context:expectedText:with:)` delegate internally to `ClipboardReplacing` (`AppKitClipboardReplacement.replace(expectedText:replacementText:targetPID:validateTarget:verifyValue:)`), returning `.success(viaClipboard: true)` on success:
   - Re-checks element identity/focus at entry and context freshness before invoking fallback, and passes a `validateTarget` closure (`isFocusedElement(element, in: target.application)`) checked before every `⌘C` / `⌘V` copy and paste attempt.
   - Inside `AppKitClipboardReplacement`, captures a full-fidelity `ClipboardSnapshot` via `AppKitClipboardManager.snapshot()` (aborting without touching the pasteboard if `ClipboardSizePolicy` marks it non-restorable), bounds the copy/paste/verification cycle to `operationBudget` (`0.45` s default), posts `⌘C` (`CGEvent.postToPid`) and verifies `expectedText`, writes the replacement string with `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` (`setTransientString`), posts `⌘V` and verifies via `kAXValueAttribute` (`verifyValue`), and checks `changeCount == ownedChangeCount` at the single restoration point—returning `.superseded` if externally modified, or calling `AppKitClipboardManager.restore(_:)` otherwise.
   - `ClipboardReplacementResult` outcomes (`.success`, `.pasteUnverified`, `.restoreFailed`, `.superseded`, `.failed`) map to `SelectionWriteFailure` cases, which `LiveFixTextUseCase` translates into `FixOutcome` values formatted by `StatusPresenter` for `HengeCoordinator.lastProbeStatusText`.

## Configuration & Lifecycle

- **Persistence & no-op write avoidance** — `JSONConfigurationStore` stores `AppConfiguration` JSON (pretty-printed, sorted keys) at `~/Library/Application Support/Henge/config.json` using atomic writes, normalized by `ConfigurationMigrator` (`currentSchemaVersion = 1`). `HengeCoordinator` guards mutations and permission/login-item refreshes with `saveConfigurationIfChanged(from:)` and equality checks so unchanged state skips redundant disk writes (logged as `DiagnosticsLabel.configSaveSkipped`).
- **Corrupt config recovery** — Empty, unreadable, or malformed config files are moved aside to `config.corrupt-<timestamp>.json` in the same folder, and `AppConfiguration.default` is written cleanly.
- **Hotkey registration & rollback** — `Shortcut` persists an optional physical `keyCode` (`UInt32?`, defaulting to `7` for `⌥X`) alongside `modifiers` so registered hotkeys remain layout-independent across active input sources (for example, when typing in Russian layout). `HotkeyRegistrar` wraps Carbon `InstallEventHandler` and `RegisterEventHotKey` using `CarbonHotkey` keycode/modifier translation (supporting ANSI keys plus extended keys such as Space, Return, arrows, and `F1`–`F12`), while `ShortcutCaptureEvaluator` validates captured events using `CarbonHotkey.systemASCIICapableLabel(forKeyCode:)` for consistent ASCII-capable key labels. When changing shortcuts in `HengeCoordinator.setShortcut(_:)`, the new shortcut is registered *before* updating `state.configuration.shortcut`; if registration fails, the error is surfaced and the previous working shortcut stays active and persisted.
- **Launch at Login & onboarding** — `SMAppServiceLoginItemManager` wraps `SMAppService.mainApp` (`ServiceManagement`), maps system states to `LoginItemStatus` (`.enabled`, `.disabled`, `.requiresApproval`), and provides `openLoginItemSettings()` (`SMAppService.openSystemSettingsLoginItems()`) when user approval is required in System Settings → Login Items. `HengeCoordinator` synchronizes login-item state on launch and permission refresh, and presents `OnboardingWindowController` on first launch when `hasCompletedOnboarding` is `false` and Accessibility permission is not yet granted.

## Localization

- **Resources & helper** — Localized strings live in `App/Localization/en.lproj/Localizable.strings` and `App/Localization/ru.lproj/Localizable.strings`. UI, status, and error messages resolve through the Foundation `L10n` helper (`Sources/Application/Localization.swift`) with explicit English `defaultValue` fallbacks.
- **Packaging & verification** — `scripts/build.sh` copies `App/Localization/*.lproj` into `Contents/Resources/` and lints both `.strings` files with `plutil -lint`. `LocalizationTests` (`Tests/HengeTests/LocalizationTests.swift`) verifies that both tables parse cleanly with matching keys and format specifiers and that every `L10n` call in `Sources/` matches both language tables.

## Diagnostic Probes

`HengeMain` intercepts `--probe` flags before initializing the SwiftUI app lifecycle and delegates to `HengeProbeRunner` (`Sources/Infrastructure/Probes/HengeProbeRunner.swift`):

```bash
swift run Henge --probe layout      # Validate RU <-> EN layout mapping
swift run Henge --probe clipboard   # Validate full-fidelity pasteboard snapshot & restore
swift run Henge --probe ax          # Inspect Accessibility focused element & selection metadata
swift run Henge --probe hotkey      # Register ⌥X for 10s and wait for a global key event
swift run Henge --probe all         # Run layout, clipboard, and ax probes
swift run Henge --probe help        # Show probe usage
```

All probes uphold Henge's privacy invariants: the clipboard probe restores the original pasteboard contents, and Accessibility probes report only roles, lengths, and range offsets — never user text, passwords, or clipboard contents.
