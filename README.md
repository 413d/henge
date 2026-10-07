# 🍥 Henge

> **Transform your mistyped text with a single hotkey.**

Henge is a lightweight, privacy-first macOS utility that instantly fixes text typed in the wrong keyboard layout. One keystroke turns `ghbdtn` into `привет` — just like a ninja transformation jutsu.

## Current Status

The repository contains the M0 project skeleton plus the **Milestone 1 native API spikes** (HEN-010 … HEN-016), implemented and covered by 40 passing unit tests:

- global hotkey via Carbon `RegisterEventHotKey` — HEN-010;
- RU ↔ EN keyboard layout mapping via Carbon TIS + `UCKeyTranslate` with a bundled ANSI fallback — HEN-011;
- Accessibility focused-element probe — HEN-012;
- Accessibility selection read — HEN-013;
- direct Accessibility selection write seam — HEN-014;
- secure-field short-circuit before any text access — HEN-015;
- full-fidelity `NSPasteboard` snapshot/restore — HEN-016.

Milestone 1 is **not closed yet**. Remaining work is manual cross-application validation on a GUI session with Accessibility permission (TextEdit, Safari, VS Code) and wiring the selection writer into the end-to-end pipeline. The text-correction pipeline itself remains deliberately deferred; the hotkey currently only resolves context and reports a safe, text-free probe status.

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
