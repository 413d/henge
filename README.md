# 🍥 Henge

> **Transform your mistyped text with a single hotkey.**

Henge is a lightweight, privacy-first macOS utility that instantly fixes text typed in the wrong keyboard layout. One keystroke turns `ghbdtn` into `привет` — just like a ninja transformation jutsu.

## Current Status

The repository currently contains the M0 project skeleton plus the first **Milestone 1** spike slice: a resident menu bar app with local JSON configuration persistence, a Carbon-based global hotkey backend, and read-only Accessibility probes for the focused element and the current selection.

Milestone 1 is **not complete yet**. Still open:

- keyboard layout mapping (`TISCopyCurrentKeyboardInputSource` / `UCKeyTranslate`) — HEN-011;
- clipboard preservation fallback — HEN-016;
- manual cross-application validation in TextEdit, Safari and VS Code (HEN-010, HEN-013, HEN-014, HEN-015);
- wiring the direct AX selection writer into the end-to-end pipeline — HEN-014.

The text-correction pipeline itself remains deliberately deferred; the hotkey currently only resolves context and reports a safe, text-free probe status.

## ✨ Features

- **One-hotkey fix** — correct the last typed word or selected text (`ru` ↔ `en`).
- **Blazing fast** — < 50 ms from keystroke to corrected text.
- **Runs in the menu bar** — no main window, just a tray icon with a context menu.
- **App exceptions** — exclude specific apps (e.g., terminal, IDE) from being modified.
- **Password-safe** — password fields are always ignored. No exceptions.
- **100% offline** — no network, no telemetry, no data leaves your Mac.
- **Auto-start** — optional launch at login.

## 🖥 Requirements

- macOS 13.0 (Ventura) or later

## 🚀 Installation

1. Download the latest `.dmg` from [Releases](../../releases).
2. Drag **Henge.app** into your `Applications` folder.
3. Launch it. The Henge icon will appear in your menu bar.

## ⌨️ Default Hotkey

| Action | Shortcut |
|---|---|
| Fix selected text or the word around the caret | `⌥X` |

You can remap it in **Settings → Hotkeys**.

## 🔒 Privacy

Henge works entirely offline. It never reads your clipboard for anything other than the correction operation, never sends data anywhere, and stores its config locally at `~/Library/Application Support/Henge/config.json`.

## 📄 License

[MIT](LICENSE)
