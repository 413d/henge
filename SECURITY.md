# Security Policy

## Supported Versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |
| < 0.1.0 | No |

## Built-In Security & Privacy Guarantees

Henge is designed as a local-first, privacy-preserving macOS utility:

- **100% offline:** Henge makes no network requests, sends no telemetry or analytics, and requires no accounts.
- **Secure text fields remain untouched:** Before reading, copying, transforming, or replacing text, Henge inspects the focused Accessibility element (`FocusedElementSnapshot.isSecure`). If the field has role or subrole `AXSecureTextField`, all inspection and replacement operations immediately return a no-op.
- **Clipboard restoration on fallback:** When an application does not support direct Accessibility text replacement and Henge falls back to copy/paste (`AppKitClipboardReplacement`), it captures a full-fidelity `ClipboardSnapshot` beforehand and restores it immediately afterward (including when replacement aborts or fails).
- **No sensitive logging:** Henge never logs user text, passwords, or clipboard contents, including when running diagnostic probes (`HengeProbeRunner`).
- **Local configuration only:** Settings are stored locally at `~/Library/Application Support/Henge/config.json`.

## Gatekeeper & Ad-Hoc Signatures on Release Builds

Public release archives (`Henge-vX.Y.Z-universal.zip`) distributed via GitHub Releases are built in CI with an **ad-hoc code signature** and are not notarized with an Apple Developer ID certificate.

1. **Verify download integrity** using the `SHA256SUMS.txt` file attached to the same release:

   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```

2. **Clear the macOS quarantine attribute** before launching `Henge.app` (adjust the path if installed in `/Applications`):

   ```bash
   xattr -dr com.apple.quarantine ~/Applications/Henge.app
   ```

3. **Build from source** if you prefer not to run Terminal commands on downloaded binaries — see [README.md](README.md#build-from-source) or [CONTRIBUTING.md](CONTRIBUTING.md).

Note: Under ad-hoc signing, macOS resets the Accessibility grant whenever `Henge.app` is replaced by a newer build; re-enable Henge in **System Settings → Privacy & Security → Accessibility** after updating.

## Reporting a Vulnerability

**Please do not open public GitHub issues or pull requests for security vulnerabilities.**

Report vulnerabilities privately using GitHub Private Vulnerability Reporting:

- **Advisory submission:** [https://github.com/413d/henge/security/advisories/new](https://github.com/413d/henge/security/advisories/new)

To help triage the issue quickly, please include:

- Henge version (and whether it was a GitHub Release build or built from source) and macOS version
- Step-by-step instructions or a minimal proof of concept to reproduce the issue
- A description of the potential security or privacy impact (for example, secure-field bypass, clipboard leakage, or unintended code execution)

We will acknowledge receipt as soon as possible and coordinate a fix before any public disclosure.
