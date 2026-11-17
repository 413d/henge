<div align="center">

<h1>🍥 Henge</h1>

**Fix mistyped keyboard layout text with a single shortcut.**

A lightweight, privacy-first macOS menu bar utility that turns `ghbdtn` into `привет` (and `руддщ` into `hello`) in one keystroke.

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-171b23?style=flat-square&logo=apple&logoColor=white)](https://github.com/413d/henge/releases/latest)
[![Universal](https://img.shields.io/badge/Apple_Silicon_%2B_Intel-Universal-24c8ec?style=flat-square&labelColor=171b23)](https://github.com/413d/henge/releases/latest)
[![MIT](https://img.shields.io/badge/license-MIT-171b23?style=flat-square)](LICENSE)

### [Download Henge ↓](https://github.com/413d/henge/releases/latest)

[Installation](#installation) · [How to Use](#how-to-use) · [Privacy & Safety](#privacy--safety) · [Limitations](#honest-limitations) · [Report an Issue](https://github.com/413d/henge/issues/new)

</div>

## Why Henge

Everyone who switches between Russian and English keyboards knows the feeling: you type a full word or sentence, look up at the screen, and see `ghbdtn` instead of `привет` — or `руддщ` instead of `hello`.

Instead of deleting everything and retyping, press **`⌥X`**. Henge converts the selected text — or the word under your cursor — without requiring you to switch layouts first.

## What It Does

| Feature | How it helps |
| --- | --- |
| **Selection or word at cursor** | Fixes your current selection, or automatically grabs the word around the caret when nothing is selected |
| **Automatic RU ↔ EN detection** | Detects layout direction from the typed characters themselves, not your active macOS input source |
| **Preserves formatting** | Keeps uppercase/lowercase letters, digits, punctuation, and `_` intact |
| **Menu bar utility** | Lives quietly in the macOS menu bar with no Dock icon or clutter |
| **Custom shortcut** | Defaults to `⌥X`; remap to any shortcut with modifiers in **Settings → General** |
| **App exceptions** | Exclude terminals, IDEs, or specific apps in **Settings → Exceptions** |
| **Launch at login** | Can start automatically when you log in (**Settings → General**) |

## Installation

**Requires macOS 13 Ventura or later.** One Universal archive supports both Apple Silicon (M1 and newer) and Intel Macs. You do not need Xcode, Swift, or Homebrew to run the pre-built app.

1. Download **`Henge-vX.Y.Z-universal.zip`** from the latest [GitHub Release](https://github.com/413d/henge/releases/latest)
   *(pick the `Henge-v*.zip` asset — GitHub's automatic `Source code` archives only contain source files).*
2. Double-click the zip to extract **`Henge.app`**, then move it to **`~/Applications`** (or **`/Applications`**).
3. **Clear Gatekeeper quarantine once before launching** *(required because public builds are ad-hoc signed without an Apple Developer ID)*:

   ```bash
   xattr -dr com.apple.quarantine ~/Applications/Henge.app
   ```

   *(If you placed it in `/Applications`, adjust the path accordingly.)*
4. Open **`Henge.app`**.
5. Grant **Accessibility** permission when prompted (or in **System Settings → Privacy & Security → Accessibility**).

### Why `xattr -dr com.apple.quarantine` is needed

Open-source releases of Henge are built on GitHub Actions with an **ad-hoc signature** and are not notarized by Apple. On macOS (especially macOS 15 Sequoia, which removed the Finder Control-Click bypass), browser downloads carry a quarantine attribute that causes macOS to block non-notarized apps.

If you prefer not to run Terminal commands on downloaded apps, you can [verify the SHA-256 checksum](#verifying-your-download) or [build from source](#build-from-source) directly on your Mac.

### Verifying your download

Download `SHA256SUMS.txt` from the same release into the folder with the zip archive and run:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

This verifies archive integrity against the CI build output.

## How to Use

1. Type text in the wrong keyboard layout (for example, `ghbdtn` or `Ghbdtn, vbh!`).
2. Either **select the text** or leave your **cursor inside / at the end of the word**.
3. Press **`⌥X`** (Option + X).

Henge replaces the text in place. You can also click the menu bar icon to:

- Toggle Henge **Enabled / Disabled**
- Trigger **Fix Text** manually
- Check **Accessibility** and shortcut registration status
- Open **Settings…** to change the shortcut, manage **Exceptions**, or toggle **Launch at Login**

## Privacy & Safety

- **100% offline.** Henge makes no network requests, sends no telemetry or analytics, and requires no account.
- **Password & secure-field protection.** Henge checks for secure text fields and refuses to read, copy, transform, or replace their contents.
- **Accessibility first, clipboard restored.** Henge reads and writes text via macOS Accessibility APIs. For apps that do not support direct Accessibility text replacement, Henge falls back to copy/paste and restores your previous clipboard contents immediately afterward.
- **Local configuration.** Settings are stored locally at `~/Library/Application Support/Henge/config.json`.

## Honest Limitations

- **RU ↔ EN only.** Only Russian and English keyboard layout mapping is supported.
- **No automatic background correction.** Henge only transforms text when you press your shortcut (or click **Fix Text**).
- **Ad-hoc signature & permissions.** Because release builds are ad-hoc signed without a Developer ID certificate, macOS resets the Accessibility grant whenever you replace `Henge.app` with a new version — re-enable Henge in **System Settings → Privacy & Security → Accessibility** after updating.
- **App compatibility varies.** Some custom UI frameworks, sandboxed apps, or remote desktop windows restrict Accessibility access; Henge fails safely as a no-op if a target field cannot be inspected or edited safely.

## Updating & Uninstalling

**Update:** Choose **Quit Henge** from the menu bar, download the new release archive, replace `Henge.app` in `~/Applications` (or `/Applications`), clear quarantine with `xattr -dr com.apple.quarantine`, and re-enable Accessibility if prompted.

**Uninstall:**

1. Disable **Launch at Login** in **Settings → General**, then click **Quit Henge**.
2. Delete `Henge.app` and its local config folder:

   ```bash
   rm -rf ~/Applications/Henge.app "$HOME/Library/Application Support/Henge"
   ```

## Build from Source

Requires macOS 13+ and Swift / Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/413d/henge.git
cd henge
./scripts/build.sh --install
open ~/Applications/Henge.app
```

Useful commands for contributors:

```bash
swift test                        # run the unit test suite
./scripts/build.sh universal      # build a universal arm64 + x86_64 bundle
./scripts/package.sh              # package dist/Henge-universal.zip + SHA256SUMS.txt
swift run Henge --probe help      # inspect native API probes (layout, ax, clipboard, hotkey)
```

To preserve macOS Accessibility permissions across local rebuilds, sign with a local Keychain certificate:

```bash
HENGE_SIGNING_IDENTITY="Henge Local" ./scripts/build.sh --install
```

Maintainers can publish a new tagged release to GitHub Releases with:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## License

[MIT](LICENSE)
