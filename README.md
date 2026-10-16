# 🍥 Henge

> **Transform your mistyped text with a single hotkey.**

Henge is a lightweight, privacy-first macOS utility that instantly fixes text typed in the wrong keyboard layout. One keystroke turns `ghbdtn` into `привет` — just like a ninja transformation jutsu.

## Current Status

The repository contains the Henge MVP implementation, including the RU ↔ EN text correction flow, configuration and menu bar lifecycle. The current unit suite passes with `swift test` (105 tests).

Henge M7 is being prepared as a Release Candidate. Live security/performance validation in real applications, Developer ID signing, notarization and clean-machine installation are still required before an RC is available. There is no stable MVP release yet.

### Native API probe harness

Native spikes can be validated from a GUI terminal (not over SSH) without launching the menu bar UI:

```bash
swift run Henge --probe help       # list probe commands
swift run Henge --probe layout     # HEN-011: RU <-> EN mapping
swift run Henge --probe clipboard  # HEN-016: snapshot -> marker -> restore
swift run Henge --probe ax         # HEN-012/013/015: focused element, selection, secure flag
swift run Henge --probe hotkey     # HEN-010: register <Option>X and wait up to 10s for a key event
```

The probes never print user text, passwords or clipboard contents; the clipboard probe restores the original pasteboard contents. Accessibility permission is required for `--probe ax` and `--probe hotkey`.

## ✨ Features

- **One-hotkey fix** — correct the last typed word or selected text (`ru` ↔ `en`).
- **Runs in the menu bar** — no main window, just a tray icon with a context menu.
- **App exceptions** — exclude specific apps (e.g., terminal, IDE) from being modified.
- **Secure-field guard** — secure fields are stopped before text operations; live app validation remains an RC gate.
- **100% offline** — no network, no telemetry, no data leaves your Mac.
- **Auto-start** — optional launch at login.

## 🖥 Requirements

- macOS 13.0 (Ventura) or later

## 🚀 Installation

### Local build (no signing identity required)

For personal testing on your own machine:

```bash
./scripts/dev/build-local.sh --install   # release build → build/Henge.app (ad-hoc signed) → /Applications/Henge.app
open /Applications/Henge.app             # launch from Finder
```

Then grant Accessibility: System Settings → Privacy & Security → Accessibility → enable Henge.

Ad-hoc signatures are device-local: rebuilding and reinstalling the app resets the
Accessibility grant — re-enable it after each reinstall.

### Release (published)

The M7 Release Candidate is not published yet. Once a release is available, download its `.dmg`, drag **Henge.app** into your `Applications` folder, then launch it. Henge requires Accessibility permission for text correction; it remains available in the menu bar if permission has not been granted.

## ⌨️ Default Hotkey

| Action | Shortcut |
|---|---|
| Fix selected text or the word around the caret | `⌥X` |

You can remap it in **Settings → Hotkeys**.

## 🔒 Privacy

Henge works entirely offline. It never reads your clipboard for anything other than the correction operation, never sends data anywhere, and stores its config locally at `~/Library/Application Support/Henge/config.json`.

## 📄 License

[MIT](LICENSE)
