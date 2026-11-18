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

- **`Sources/App/`** — Application entry point and composition root: `HengeMain` (`HengeApp.swift`, intercepts `--probe` before launching `HengeApp`), `AppDelegate` (sets `.accessory` activation policy and triggers the initial Accessibility prompt), and `AppEnvironment` (wires live dependencies).
- **`Sources/UI/`** — SwiftUI menu-bar popover and preferences window: `MenuBarView` (`MenuBar/MenuBarView.swift`) and `SettingsView` (`Settings/SettingsView.swift`). UI views bind to `HengeCoordinator` and contain no business or Accessibility logic.
- **`Sources/Application/`** — Orchestration and state management: `HengeCoordinator` (`HengeCoordinator.swift`), `ApplicationState` (`ApplicationState.swift`), and `FixTextUseCaseProtocol` / `LiveFixTextUseCase` (`FixTextUseCase.swift`).
- **`Sources/Domain/`** — Pure business logic with **zero** imports of `AppKit`, `SwiftUI`, `ApplicationServices`, `Carbon`, or `ServiceManagement` (only `Foundation`, or pure Swift):
  - `Layout/` — `Layout`, `LayoutDetecting` / `MajorityLayoutDetector`, `LayoutMapping`, `CasePreserving` / `DefaultCasePreserver`, `WordBoundaryDetecting` / `DefaultWordBoundaryDetector`, and `TextTransforming` / `SimpleTextTransformer`.
  - `Applications/` — `ApplicationIdentity`, `ExceptionMatcher`, and `ExceptionManager`.
  - `Hotkey/` — `Shortcut` and `Shortcut.Modifiers`.
- **`Sources/Configuration/`** — Local persistence and schema migration: `AppConfiguration`, `ConfigurationMigrator`, and `ConfigurationStore` (`JSONConfigurationStore` and `InMemoryConfigurationStore`).
- **`Sources/Infrastructure/`** — Protocol-backed macOS adapters:
  - `AppRuntime.swift` — `AppRuntime`, `LiveAppRuntime` (Accessibility element inspection and text replacement), `GlobalHotkeyCenter`, and `CarbonHotkey`.
  - `Applications/ActiveApplicationProvider.swift` — `ActiveApplicationProviding` and `WorkspaceActiveApplicationProvider`.
  - `Layout/NativeKeyboardLayoutMapper.swift` — `NativeKeyboardLayoutMapper` implementing `LayoutMapping` via Carbon TIS and `UCKeyTranslate` (with a bundled ANSI fallback table for headless or restricted environments).
  - `Clipboard/` — `ClipboardManaging`, `AppKitClipboardManager`, `ClipboardReplacing`, `AppKitClipboardReplacement`, and `ClipboardSnapshot`.
  - `Lifecycle/` — `LoginItemManaging` and `SMAppServiceLoginItemManager`.
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

1. **Enabled check** — `HengeCoordinator` unregisters the global hotkey while disabled and treats `canTriggerFixText` as `false`. The app stays resident in the menu bar without acting on keystrokes.
2. **Excluded applications** — `ExceptionMatcher` checks the active application's bundle identifier (resolved by `WorkspaceActiveApplicationProvider`) against `AppConfiguration.excludedApplicationBundleIdentifiers`. Both `HengeCoordinator.handleFixTextHotkey()` and `LiveFixTextUseCase.execute(...)` abort immediately for excluded apps.
3. **Accessibility permission** — `LiveAppRuntime.hasAccessibilityPermission` (`AXIsProcessTrusted()`) must be `true`. Missing permission halts execution safely and updates the UI status.
4. **Secure-field guard** — `LiveAppRuntime.resolveFocusedElement()` inspects `kAXRoleAttribute` and `kAXSubroleAttribute`. If either equals `"AXSecureTextField"`, `FocusedElementSnapshot.isSecure` is `true`. Both `HengeCoordinator` and every read/write method on `LiveAppRuntime` (`inspectSelection()`, `inspectTextContext()`, `replaceText(...)`, `replaceTextUsingClipboard(...)`) refuse to read, copy, transform, or replace content in secure fields.

### 2. Target Text Resolution

`LiveAppRuntime.inspectTextContext()` determines what text to transform:

- **Active selection first** — If `kAXSelectedTextRangeAttribute` has `length > 0`, `kAXSelectedTextAttribute` is read and transformed directly.
- **Word around caret** — If no text is selected (`isCaretContext == true`), `LiveFixTextUseCase` reads the element's `kAXValueAttribute` and caret UTF-16 offset, then delegates to `DefaultWordBoundaryDetector` (`WordBoundaryDetecting`) to locate the contiguous word around (or immediately adjacent to) the caret, treating letters, decimal digits, and `_` as word characters.

### 3. Layout Direction Detection & Character Mapping

- **Direction from text, not input source** — `MajorityLayoutDetector` (`LayoutDetecting`) counts English (Basic Latin) vs. Russian (Cyrillic) letters in the target text. Ties or neutral text (digits/punctuation only) produce `.noOp(.ambiguousDirection)` or `.noOp(.neutralText)`.
- **Physical key mapping** — `NativeKeyboardLayoutMapper` queries Carbon TIS (`com.apple.keylayout.US` and `com.apple.keylayout.Russian` / `com.apple.keylayout.RussianWin`) and `UCKeyTranslate` to build bidirectional key maps, falling back to an ANSI table when system layout data is unavailable.
- **Formatting preservation** — `SimpleTextTransformer` combines `NativeKeyboardLayoutMapper` with `DefaultCasePreserver` (`CasePreserving`) to preserve uppercase/lowercase casing, digits, whitespace, `_`, and trailing delimiter punctuation.

### 4. Replacement (Accessibility Primary, Clipboard Fallback)

1. **Direct Accessibility replacement (primary)** — `LiveAppRuntime.replaceText(...)` verifies that focus and text context have not shifted, updates `kAXSelectedTextRangeAttribute` if expanding a caret word, writes `kAXSelectedTextAttribute` via `AXUIElementSetAttributeValue`, and moves the caret to the end of the replaced text.
2. **Clipboard copy/paste fallback** — Only when direct Accessibility replacement returns `.unavailable(.unsupported)` does `LiveFixTextUseCase` invoke `LiveAppRuntime.replaceTextUsingClipboard(...)` → `AppKitClipboardReplacement`:
   - Captures a full-fidelity `ClipboardSnapshot` (all pasteboard items and UTI data representations) via `AppKitClipboardManager.snapshot()`.
   - Verifies focus and target PID, posts `⌘C` (`CGEvent.postToPid`), waits for `pasteboard.changeCount` to advance, and checks that the copied string matches `expectedText`.
   - Writes the replacement string, posts `⌘V`, waits for `kAXValueAttribute` verification, and restores the original `ClipboardSnapshot` (guaranteed via `defer` even on early abort or failure).

## Configuration & Lifecycle

- **Persistence** — `JSONConfigurationStore` stores `AppConfiguration` JSON (pretty-printed, sorted keys) at `~/Library/Application Support/Henge/config.json` using atomic writes, normalized by `ConfigurationMigrator` (`currentSchemaVersion = 1`).
- **Corrupt config recovery** — Empty, unreadable, or malformed config files are moved aside to `config.corrupt-<timestamp>.json` in the same folder, and `AppConfiguration.default` is written cleanly.
- **Hotkey registration & rollback** — `GlobalHotkeyCenter` wraps Carbon `InstallEventHandler` and `RegisterEventHotKey` using `CarbonHotkey` keycode/modifier translation. When changing shortcuts in `HengeCoordinator.setShortcut(_:)`, the new shortcut is registered *before* updating `state.configuration.shortcut`; if registration fails, the error is surfaced and the previous working shortcut stays active and persisted.
- **Launch at Login** — `SMAppServiceLoginItemManager` wraps `SMAppService.mainApp` (`ServiceManagement`) and synchronizes its state with `AppConfiguration.launchAtLogin` on launch and permission refresh.

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
