# Contributing to Henge

Thank you for helping improve Henge! This guide covers local setup, build and test workflows, and the invariants every change must uphold.

## Development Requirements

- **macOS 13 Ventura** or later
- **Swift 6.0** (Xcode 16+ or Xcode Command Line Tools via `xcode-select --install`)

## Quick Start

```bash
git clone https://github.com/413d/henge.git
cd henge
```

Common contributor commands:

```bash
# Run the unit test suite
swift test

# Build a native .app bundle (build/Henge.app)
./scripts/build.sh native

# Build and install locally to ~/Applications/Henge.app
./scripts/build.sh --install

# Build a universal arm64 + x86_64 bundle (build/universal/Henge.app)
./scripts/build.sh universal

# Package dist/Henge-universal.zip, dist/SHA256SUMS.txt, and dist/LICENSE.txt
./scripts/package.sh

# Inspect native API probes (layout, clipboard, ax, hotkey, all, help)
swift run Henge --probe help
```

To avoid re-granting Accessibility permissions after every local rebuild, sign with a local Keychain certificate:

```bash
HENGE_SIGNING_IDENTITY="Henge Local" ./scripts/build.sh --install
```

### Release Candidate Script (Maintainers Only)

`scripts/release/create-rc.sh` builds, signs, notarizes, and staples an `.xcarchive` and `.dmg` using `Henge.xcodeproj`. It requires Apple Developer ID and notarization credentials (`HENGE_TEAM_ID`, `HENGE_SIGNING_IDENTITY`, `HENGE_NOTARY_PROFILE`) and is intended only for maintainers cutting signed releases. Contributors should use `./scripts/build.sh`, `./scripts/package.sh`, or Xcode with ad-hoc signing (`-`).

## Architecture & Coding Guidelines

See [docs/architecture.md](docs/architecture.md) for the full system overview and safety invariants.

- **Zero third-party dependencies:** Use native Swift and macOS frameworks (`SwiftUI`, `AppKit`, `ApplicationServices`, `Carbon`, `ServiceManagement`). Do not add external packages unless strictly justified.
- **Keep `Sources/Domain/` pure:** Domain types must never import `AppKit`, `SwiftUI`, `ApplicationServices`, `Carbon`, or `ServiceManagement` (only `Foundation` when needed).
- **Prefer protocol boundaries:** Wrap macOS-specific APIs behind protocols (`AppRuntime`, `ClipboardManaging`, `LoginItemManaging`, `ConfigurationStore`) so application and domain logic stay unit-testable.
- **Never weaken safety or privacy invariants:**
  - Never read, copy, transform, or replace content in secure text fields (`AXSecureTextField` / `FocusedElementSnapshot.isSecure`).
  - Excluded applications (`ExceptionMatcher`) and disabled state must remain strict no-ops.
  - Never log user text, passwords, or clipboard contents.
  - Always restore the original `ClipboardSnapshot` after fallback replacement.
- **Write unit tests:** Add or update tests under `Tests/HengeTests/` for changes to domain, configuration, or application logic, and manually verify Accessibility behavior against real macOS apps when modifying `Sources/Infrastructure/`.

## Pull Request Checklist

- [ ] `swift test` passes with no failures.
- [ ] Bundle/script checks pass (`plutil -lint App/Info.plist`, and `./scripts/build.sh native` or `./scripts/package.sh` if build/packaging files changed).
- [ ] `README.md`, `docs/architecture.md`, and `CHANGELOG.md` are updated when user-facing behavior, architecture, or scripts change.
- [ ] No build artifacts (`build/`, `.build/`, `dist/`), local configs, or unrelated changes are committed.
- [ ] The pull request is focused on a single clear problem or improvement.
