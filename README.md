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

For personal testing on your own machine (built with Swift CLI, Xcode not required):

```bash
# Build native bundle for current Mac:
./scripts/build.sh                       # creates build/Henge.app (ad-hoc signed)

# Build and install to ~/Applications (recommended):
./scripts/build.sh --install             # installs to ~/Applications/Henge.app
open ~/Applications/Henge.app            # launch

# Or install to system /Applications:
./scripts/build.sh --install /Applications

# Build universal bundle (Apple Silicon arm64 + Intel x86_64):
./scripts/build.sh universal             # creates build/universal/Henge.app

# Package universal zip archive with SHA-256 sums:
./scripts/package.sh                     # creates dist/Henge-universal.zip + dist/SHA256SUMS.txt
./scripts/package.sh --archive-name Henge-v0.1.0-universal.zip  # custom archive name
```

Then grant Accessibility: System Settings → Privacy & Security → Accessibility → enable Henge.

Ad-hoc signatures are device-local: rebuilding and reinstalling the app resets the
Accessibility grant — re-enable it after each reinstall.

> **Tip (`HENGE_SIGNING_IDENTITY`):** To preserve Accessibility permissions in TCC across rebuilds, create a local Code Signing certificate in Keychain Access (e.g., `"Henge Local"`) and specify it via `HENGE_SIGNING_IDENTITY`:
>
> ```bash
> HENGE_SIGNING_IDENTITY="Henge Local" ./scripts/build.sh --install
> ```

### GitHub Releases (pre-built ad-hoc downloads)

Tagged releases (`v*`) are built automatically by `.github/workflows/release.yml` and published to the **GitHub Releases** tab as universal (`arm64` + `x86_64`) `.zip` archives with SHA-256 checksums.

Because these open-source builds are **ad-hoc signed** without a paid Apple Developer ID / notarization, macOS flags browser downloads with Gatekeeper quarantine (and macOS 15 Sequoia removed the Finder Control-Click bypass). To install from GitHub Releases:

1. Download `Henge-vX.Y.Z-universal.zip` (and optionally `SHA256SUMS.txt`) from [Releases](../../releases).
2. *(Optional)* Verify the archive checksum:
   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```
3. Unzip the archive and move **Henge.app** to `~/Applications/` (or `/Applications/`).
4. Remove the Gatekeeper quarantine attribute before launching:
   ```bash
   xattr -cr ~/Applications/Henge.app
   ```
5. Launch **Henge.app** and enable **Accessibility** access in **System Settings → Privacy & Security → Accessibility**.

To publish a new GitHub Release, push a version tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

> **Note on Notarized Releases:** A separate Developer ID + notarized `.dmg` release path (`scripts/release/create-rc.sh`) exists for signed distribution when Apple Developer credentials are available.

### GitHub Actions CI artifacts (development builds)

Every push to `main` also uploads an ad-hoc `henge-macos-universal` artifact (retained for 14 days) on the workflow run summary for development testing. The same `xattr -cr` quarantine removal step applies after downloading.

## ⌨️ Default Hotkey

| Action | Shortcut |
|---|---|
| Fix selected text or the word around the caret | `⌥X` |

You can remap it in **Settings → Hotkeys**.

## 🔒 Privacy

Henge works entirely offline. It never reads your clipboard for anything other than the correction operation, never sends data anywhere, and stores its config locally at `~/Library/Application Support/Henge/config.json`.

## 📄 License

[MIT](LICENSE)
