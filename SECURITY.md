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
- **Clipboard restoration on fallback:** When an application does not support direct Accessibility text replacement and Henge falls back to `⌘C`/`⌘V` copy/paste (`AppKitClipboardReplacement`), it captures a full-fidelity `ClipboardSnapshot` beforehand and restores it at a single restoration point afterward (including when replacement aborts or fails), subject to these protections:
  - **Bounded ~450 ms residual window:** The entire copy, transient paste, and verification cycle is capped by a single `operationBudget` (`0.45` seconds), minimizing the window during which the temporary replacement string sits on the pasteboard.
  - **Transient & concealed pasteboard markers:** The temporary replacement write attaches `org.nspasteboard.TransientType` and `org.nspasteboard.ConcealedType` (`ReplacementPasteboard.setTransientString(_:)`) so compliant clipboard managers do not record the intermediate text.
  - **`changeCount` ownership guard:** `AppKitClipboardReplacement` records `ownedChangeCount` when writing the replacement string. If another copy advances `pasteboard.changeCount` before restoration, Henge returns `.superseded` and skips restoring the earlier snapshot so newer user clipboard contents are never overwritten.
  - **32 MiB representation limit:** `ClipboardSizePolicy` enforces a `33_554_432`-byte (`32 * 1024 * 1024`) cap on non-exempt pasteboard representations; if an item exceeds that cap (`ClipboardSnapshot.isRestorable == false`), Henge aborts the clipboard fallback before touching the pasteboard.
  - **Guaranteed non-empty restoration with plain-text fallback:** `AppKitClipboardManager.restore(_:)` attempts a full-fidelity multi-UTI restore (`PasteboardBacking.writeObjects(_:)`). If that rich pasteboard item restoration fails, Henge falls back to restoring plain text when UTF-8, UTF-16 with BOM handling, plain text, or RTF data is present (`plainTextFallback(in:)`) so the clipboard is not left empty; if no plain-text or RTF representation exists, restoration fails and the operation surfaces `.clipboardRestoreFailed`.
- **No sensitive logging:** Henge never logs user text, passwords, or clipboard contents, including when running diagnostic probes (`HengeProbeRunner`). Structured logs emitted through `Diagnostics` (`os.Logger` under subsystem `io.github.413d.Henge`) record only static `DiagnosticsLabel` events, counts, `DiagnosticsLengthBucket` buckets, and validated bundle identifiers or pasteboard UTI names.
- **Local configuration only:** Settings are stored locally at `~/Library/Application Support/Henge/config.json`.

## Gatekeeper & Ad-Hoc Signatures on Release Builds

Public release archives (`Henge-vX.Y.Z-universal.zip`) distributed via GitHub Releases are built in CI with an **ad-hoc code signature** and are not notarized with an Apple Developer ID certificate.

1. **Automated checksum-verified installation (Homebrew or `install.sh`):**
   - **Homebrew (`Casks/henge.rb`):** `brew tap 413d/henge https://github.com/413d/henge && brew install --cask 413d/henge/henge` verifies the pinned SHA-256 checksum and clears `com.apple.quarantine` during `postflight_steps`.
   - **Installer script (`scripts/install.sh`):** `curl -fsSL https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh | bash` verifies `SHA256SUMS.txt` *before* extraction, checks `codesign --verify --deep --strict` and `CFBundleIdentifier == io.github.413d.Henge`, and clears `com.apple.quarantine`.

2. **Manual `.zip` verification & first-launch Gatekeeper approval:**
   - Verify download integrity using `SHA256SUMS.txt` attached to the release:

     ```bash
     shasum -a 256 -c SHA256SUMS.txt
     ```

   - Allow first launch using **either** method:
     - **Apple's official GUI flow:** Attempt to open `Henge.app` once (click **Done** on the unverified-app prompt), then open **System Settings → Privacy & Security**, scroll to **Security**, click **Open Anyway** next to Henge, and confirm.
     - **Terminal quarantine removal** (adjust path if installed in `/Applications`):

       ```bash
       xattr -dr com.apple.quarantine ~/Applications/Henge.app
       ```

3. **Build from source** if you prefer compiling locally — see [README.md](README.md#build-from-source) or [CONTRIBUTING.md](CONTRIBUTING.md).

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
