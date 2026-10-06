# 🍥 Henge

> **Transform your mistyped text with a single hotkey.**

Henge is a lightweight, privacy-first macOS utility that instantly fixes text typed in the wrong keyboard layout. One keystroke turns `ghbdtn` into `привет` — just like a ninja transformation jutsu.

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

## ⌨️ Default Hotkeys

| Action | Shortcut |
|---|---|
| Fix last word | `Ctrl + Shift + X` |
| Fix selected text | `Ctrl + Shift + C` |

You can remap both in **Settings → Hotkeys**.

## 🔒 Privacy

Henge works entirely offline. It never reads your clipboard for anything other than the correction operation, never sends data anywhere, and stores its config locally at `~/Library/Application Support/Henge/config.json`.

## 📄 License

[MIT](LICENSE)
