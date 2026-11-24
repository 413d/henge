<div align="center">

<img src="site/assets/icon-256.png" width="128" height="128" alt="Henge app icon">

<h1>Henge</h1>

**Fix mistyped keyboard layout text with a single shortcut.**

A lightweight, privacy-first macOS menu bar utility that turns `ghbdtn` into `привет` (and `руддщ` into `hello`) in one keystroke.

[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-171b23?style=flat-square&logo=apple&logoColor=white)](https://github.com/413d/henge/releases/latest)
[![Universal](https://img.shields.io/badge/Apple_Silicon_%2B_Intel-Universal-24c8ec?style=flat-square&labelColor=171b23)](https://github.com/413d/henge/releases/latest)
[![MIT](https://img.shields.io/badge/license-MIT-171b23?style=flat-square)](LICENSE)

### [Download Henge ↓](https://github.com/413d/henge/releases/latest)

**English** · [Русский](README.ru.md)

[Website](https://413d.github.io/henge/) · [Installation](#installation) · [How to Use](#how-to-use) · [Privacy & Safety](#privacy--safety) · [Limitations](#honest-limitations) · [Report an Issue](https://github.com/413d/henge/issues/new)

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

**Requires macOS 13 Ventura or later.** One Universal archive supports both Apple Silicon (M1 and newer) and Intel Macs.

### Option 1 — Homebrew (Recommended, no quarantine prompt)

```bash
brew tap 413d/henge https://github.com/413d/henge
brew install --cask 413d/henge/henge
```

Homebrew verifies the release SHA-256 checksum, installs `Henge.app`, and strips `com.apple.quarantine` automatically during `postflight_steps`.

### Option 2 — One-command installer (no Homebrew needed)

```bash
curl -fsSL https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh | bash
```

Verifies the GitHub Release `SHA256SUMS.txt` **before** unpacking, checks the `codesign` signature and bundle identifier, clears `com.apple.quarantine`, and installs to `/Applications` (or `~/Applications` if `/Applications` is not writable — no `sudo` required).

### Option 3 — Manual `.zip` download

1. Download **`Henge-vX.Y.Z-universal.zip`** from the latest [GitHub Release](https://github.com/413d/henge/releases/latest)
   *(pick the `Henge-v*.zip` asset — GitHub's automatic `Source code` archives only contain source files; `INSTALL.txt` is bundled inside).*
2. Double-click the zip to extract **`Henge.app`**, then move it to **`/Applications`** or **`~/Applications`**.
3. **Allow first launch through macOS Gatekeeper** *(public builds are ad-hoc signed without a paid Apple Developer ID)* — choose **either** method:
   - **GUI (Apple's official instruction — no Terminal needed):** Double-click `Henge.app` once and click **Done** (or **OK**) on the unverified-app prompt, then open **System Settings → Privacy & Security**, scroll to the **Security** section, click **Open Anyway** next to Henge, and confirm.
   - **Terminal:** Clear the quarantine attribute once before opening:

     ```bash
     xattr -dr com.apple.quarantine ~/Applications/Henge.app
     ```

     *(Adjust to `/Applications/Henge.app` if installed system-wide.)*
4. Open **`Henge.app`** and grant **Accessibility** permission when prompted (or in **System Settings → Privacy & Security → Accessibility**).

### Why Gatekeeper prompts on manual `.zip` downloads

Open-source releases of Henge are built transparently on GitHub Actions with an **ad-hoc signature** and are not notarized with a paid Apple Developer ID. Browser downloads carry `com.apple.quarantine`, which causes macOS (especially macOS 15 Sequoia) to ask for explicit confirmation on first launch via **System Settings → Privacy & Security → Open Anyway** or `xattr -dr com.apple.quarantine`. Homebrew and `install.sh` verify the release checksum and clear quarantine automatically, or you can [build from source](#build-from-source) directly on your Mac.

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

**Update:**
- **Homebrew:** `brew upgrade --cask 413d/henge/henge`
- **Installer script:** re-run `curl -fsSL https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh | bash`
- **Manual `.zip`:** Choose **Quit Henge** from the menu bar, replace `Henge.app` in `/Applications` or `~/Applications`, allow first launch via **System Settings → Privacy & Security → Open Anyway** or `xattr -dr com.apple.quarantine`, and re-enable **Accessibility** if prompted.

**Uninstall:**

1. Disable **Launch at Login** in **Settings → General**, then click **Quit Henge**.
2. Remove Henge (`brew uninstall --cask 413d/henge/henge` if installed via Homebrew) and delete its local config folder:

   ```bash
   rm -rf /Applications/Henge.app ~/Applications/Henge.app "$HOME/Library/Application Support/Henge"
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

Maintainers can publish a new tagged release to GitHub Releases (for stable tags, the `Release` workflow automatically updates `Casks/henge.rb` on `main` after uploading `SHA256SUMS.txt`):

```bash
git tag v0.2.0
git push origin v0.2.0
# Manual fallback if needed:
./scripts/release/update-cask.sh --no-downgrade 0.2.0 <sha256>
```

## License

[MIT](LICENSE)
