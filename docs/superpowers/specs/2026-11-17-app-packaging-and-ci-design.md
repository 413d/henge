# App Packaging & GitHub Actions CI/CD Design

**Date:** 2026-11-17  
**Topic:** App Packaging and CI Workflow for Henge  

## 1. Intent & Context

Henge is a resident macOS menu-bar utility written in Swift. It is built using Swift CLI (`swift build`) without Xcode project reliance for everyday development.

Currently:
- An ad-hoc packaging script exists in `scripts/dev/build-local.sh`, but it only targets the host architecture, hardcodes installation to `/Applications` (requiring admin rights), and is located under `dev/`.
- There is no automated packaging script for universal (arm64 + x86_64) distribution.
- There is no GitHub Actions workflow (`.github/workflows/`) for automated testing, bundle verification, packaging, and artifact publishing on push to `main`.

## 2. Goals & Non-Goals

### Goals
- Provide `scripts/build.sh` supporting:
  - `native` (fast local iteration on host arch) and `universal` (arm64 + x86_64 via `lipo`).
  - Standard `.app` structure: `Contents/{MacOS,Resources}`.
  - Materialized `Info.plist` with required keys (`CFBundleName`, `CFBundleIdentifier`, `CFBundleExecutable`, `CFBundleInfoDictionaryVersion`, `CFBundlePackageType`, `CFBundleShortVersionString`, etc.).
  - Copying executable with `chmod +x` and app icon (`App/Henge.icns`) when present.
  - Ad-hoc codesigning (`codesign --force --deep --sign -`).
  - Strict verification of bundle structure, Info.plist, executable bit, and ad-hoc signature.
  - Optional `--install` flag installing to `~/Applications` by default (creating the directory if needed) or `/Applications` when specified.
- Provide `scripts/package.sh`:
  - Builds universal `.app`.
  - Packages it into `dist/Henge-universal.zip`.
  - Computes `dist/SHA256SUMS.txt`.
- Backward compatibility: keep `scripts/dev/build-local.sh` working (delegating to or mirroring `scripts/build.sh`).
- Provide `.github/workflows/ci.yml`:
  - Triggers: `push` to `main`, `pull_request`, `workflow_dispatch`.
  - Runs on `macos-14` or `macos-15` (Apple Silicon runner).
  - Validates bash scripts (`bash -n`), lints Info.plist (`plutil -lint`).
  - Runs test suite (`swift test`).
  - Builds universal app bundle & archive via `scripts/package.sh`.
  - Verifies checksums with `shasum -a 256 -c`.
  - Uploads bundle artifact (`dist/Henge-universal.zip` + `dist/SHA256SUMS.txt`) to GitHub Actions Artifacts with 14-day retention.
- Update GBrain documentation (`~/brain/Projects/henge`) per AGENTS.md.

### Non-Goals
- Developer ID signing and Apple Notarization (covered separately in `scripts/release/create-rc.sh` with Keychain credentials).
- Creating DMG installer (local ad-hoc runs are distributed via `.app` / `.zip`).

## 3. Architecture & Interfaces

### File Locations
- `scripts/build.sh`: Main build and bundle assembly script.
- `scripts/package.sh`: Packaging script for distribution archive.
- `scripts/dev/build-local.sh`: Legacy wrapper redirecting to `scripts/build.sh`.
- `.github/workflows/ci.yml`: CI/CD workflow definition.

### CLI Signatures
- `./scripts/build.sh [native|universal] [--install [TARGET_DIR]] [--debug|--release]`
  - Defaults: `native`, `--release`, target directory `$HOME/Applications`.
- `./scripts/package.sh`
  - Packages `build/universal/Henge.app` into `dist/Henge-universal.zip` + `dist/SHA256SUMS.txt`.

### Info.plist Template
- Sourced from `App/Info.plist`.
- Materializes:
  - `$(PRODUCT_BUNDLE_IDENTIFIER)` -> `io.github.henge.Henge`
  - `$(MARKETING_VERSION)` -> `0.1.0` (or from config / git)
  - `$(CURRENT_PROJECT_VERSION)` -> `2`
  - `$(EXECUTABLE_NAME)` -> `Henge`
