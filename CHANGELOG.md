# Changelog

All notable changes to Henge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **Xcode CI verification job** in `.github/workflows/ci.yml` (`xcode` job) running `plutil -lint Henge.xcodeproj/project.pbxproj` and building the `Henge` scheme on `macos-15`.
- **Typed `os.Logger` diagnostics facade** (`Diagnostics`, `DiagnosticsCategory`, `DiagnosticsLabel`, `DiagnosticsLengthBucket`) under subsystem `io.github.413d.Henge` with ASCII validation for bundle identifiers and UTI names and zero user-text logging.
- **32 MiB clipboard snapshot size policy** (`ClipboardSizePolicy`) that skips the copy/paste fallback before modifying the pasteboard when non-exempt representations exceed `33_554_432` bytes.
- **Transient/concealed pasteboard markers and fallback outcome reporting** — marks temporary replacement writes with `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` (`ReplacementPasteboard.setTransientString(_:)`) and reports `ClipboardReplacementResult` outcomes via `SelectionWriteFailure`.
- **Single-instance guard** (`SingleInstanceGuard`) in `HengeMain` activating an already-running Henge instance and exiting duplicates (exempting `--probe` invocations and processes without a bundle identifier).
- **Structured text-fixing outcomes** (`FixOutcome`, `FixFailureReason`) surfacing clear, localized status messages for direct replacement, clipboard fallback, missing permission or focus, secure fields, exclusions, and clipboard restoration states.
- **Layout-independent shortcut recording and extended keys** — stores the physical hardware `keyCode` alongside modifiers in `Shortcut` so hotkeys work reliably regardless of the active keyboard layout, adds support for arrow keys, `F1`–`F12`, Space, and Return, and migrates legacy default `⌥X` settings.
- **State-aware menu bar icon and badges** (`MenuBarIconState`, `MenuBarIconLabel`) rendering distinct visual states for active, disabled (dimmed), missing Accessibility permission (dot badge), and degraded shortcut registration (ring badge) states with localized accessibility descriptions.
- **Launch at Login approval status handling** (`LoginItemStatus.requiresApproval`) detecting when macOS requires user approval in System Settings and exposing an **Open Login Items…** shortcut in Settings without dropping the saved preference.
- **One-click frontmost application exclusion** in the menu bar popover allowing users to exclude the previously active application directly without opening Settings.
- **English and Russian localization** (`en.lproj`, `ru.lproj`) across the menu bar popover, Settings, onboarding, error states, and accessibility labels via the Foundation `L10n` helper.
- **First-launch onboarding window** (`OnboardingView`, `OnboardingWindowController`) introducing the shortcut and offline privacy guarantees and guiding users through granting Accessibility permission on initial launch when not yet authorized.

### Changed

- **Bounded clipboard fallback budget** (`AppKitClipboardReplacement`) capping the entire copy, transient paste, and verification cycle to a single `0.45`-second `operationBudget`.
- **Single workspace activation source** — routes `NSWorkspace.didActivateApplicationNotification` handling through `WorkspaceActiveApplicationProvider` (`setActivationHandler(_:)`), removing duplicate workspace observers from `MenuBarView`.
- **Event-based application activation wait** (`ActivationWaiter`) awaiting workspace activation notifications with a timeout instead of tight Accessibility polling when restoring focus before menu-bar `Fix Text`.
- **No-op configuration write avoidance** in `HengeCoordinator` (`saveConfigurationIfChanged(from:)`) so unchanged configuration or status refreshes skip redundant `config.json` writes.
- **Fast UTF-16 index math** in `LiveFixTextUseCase` using native `String.Index` UTF-16 offset conversion instead of materializing full-document character arrays during caret and range mapping.
- **Bounded caret window for word-boundary detection** (`DefaultWordBoundaryDetector`) scanning at most 256 delimiter characters on each side of the caret to keep corrections responsive in large documents while continuing through arbitrarily long word runs without truncation.
- **Cached Accessibility trust check** (`AccessibilityPermissionProbe`) caching `AXIsProcessTrusted()` for 1 second to avoid repeated `tccd` IPC round trips during UI refreshes, while invalidating immediately on app activation, permission prompts, or opening System Settings.
- **Single focused-element resolution per operation** (`TextTarget`, `TextContext`) resolving the focused Accessibility element once in `inspectTextContext(in:)` and reusing it across direct and clipboard replacement paths with identity and freshness validation before writing.
- **Modular infrastructure service layout** splitting `AppRuntime.swift` into focused services (`AccessibilityTextService`, `AccessibilitySnapshots`, `AccessibilityPermissionProbe`, `TextTarget`, `HotkeyRegistrar`, `KeyboardLabel`, `ApplicationActivator`) behind the thin `LiveAppRuntime` facade.
- **Extracted status presentation** (`StatusPresenter`) moving user-facing hotkey, login item, fix-outcome, and icon-state formatting out of `HengeCoordinator`, alongside simplified `canTriggerFixText` evaluation (`state.configuration.isEnabled`).

### Fixed

- **Plain-text clipboard restore fallback** (`AppKitClipboardManager.restore(_:)` + `PasteboardBacking`) extracting plain text (UTF-8, UTF-16 with BOM handling, plain text, or RTF) when multi-UTI pasteboard restoration fails, preventing an empty clipboard.
- **Concurrent clipboard copy protection** (`ownedChangeCount` supersede guard in `AppKitClipboardReplacement`) returning `.superseded` and skipping snapshot restoration when the user copies newer content during the fallback window.
- **Onboarding permission polling lifecycle** stopping background Accessibility polling immediately when the onboarding window closes or dismisses.
- **Activation wait timeout clamping** (`ActivationWaiter.sleepNanoseconds(for:)`) guarding against `NaN`, non-finite, non-positive, and oversized timeouts (clamped to 60 seconds) so `Task.sleep` never traps.

### Removed

- **Deferred fix-text placeholder and test-environment sniffing** — removed the temporary deferred-use-case and availability scaffolding, and replaced process-name/environment heuristics with explicit headless initializers (`NativeKeyboardLayoutMapper.bundled()` and explicit ASCII-label injection in `CarbonHotkey`).

## [0.1.0]

Initial open-source release of Henge for macOS 13 Ventura and later.

### Added

- **RU ↔ EN keyboard layout conversion** driven by macOS system layout data (Carbon TIS / `UCKeyTranslate`) with a bundled ANSI fallback table.
- **Selection or word-at-caret fixing** — transforms the active selection when present, or automatically detects the word around the caret (`Letters`, digits, and `_`).
- **Automatic direction detection** inferred from the typed characters themselves rather than the active macOS input source.
- **Formatting preservation** keeping letter casing, digits, whitespace, `_`, and contextual punctuation intact.
- **Accessibility-first replacement with clipboard fallback** — writes via `AXSelectedText` as the primary path and falls back to copy/paste (`AppKitClipboardReplacement`) with full-fidelity clipboard snapshot restoration when direct Accessibility editing is unsupported.
- **Safety and privacy guardrails** — strictly ignores secure/password fields (`AXSecureTextField`), honors per-application exclusions (`Settings → Exceptions`), acts as a complete no-op when disabled, and never logs user text, passwords, or clipboard contents.
- **Customizable global shortcut** defaulting to `⌥X`, with rollback to the previous active shortcut if registration fails.
- **Menu bar utility and Settings UI** with enable/disable toggle, manual **Fix Text** action, Accessibility permission status, shortcut recorder, and application exception picker.
- **Launch at Login** integration via `SMAppService` and local JSON configuration at `~/Library/Application Support/Henge/config.json` with automatic backup recovery for corrupt files.
- **Universal macOS builds (`arm64` + `x86_64`)** and packaging scripts (`scripts/build.sh`, `scripts/package.sh`) with `SHA256SUMS.txt` verification and `--probe` CLI diagnostics (`HengeProbeRunner`).

[Unreleased]: https://github.com/413d/henge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/413d/henge/releases/tag/v0.1.0
