# Changelog

All notable changes to Henge will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

Initial open-source release of Henge for macOS 13 Ventura and later.

### Added

- **RU ↔ EN keyboard layout conversion** driven by macOS system layout data (Carbon TIS / `UCKeyTranslate`) with a bundled ANSI fallback table.
- **Selection or word-at-caret fixing** — transforms the active selection when present, or automatically detects the word around the caret (`Letters`, digits, and `_`).
- **Automatic direction detection** inferred from the typed characters themselves rather than the active macOS input source.
- **Formatting preservation** keeping letter casing, digits, whitespace, `_`, and contextual punctuation intact.
- **Accessibility-first replacement with clipboard fallback** — writes via `AXSelectedText` as the primary path and falls back to copy/paste (`AppKitClipboardReplacement`) with full-fidelity clipboard snapshot restoration when direct Accessibility editing is unsupported.
- **Safety and privacy guardrails** — strictly ignores secure/password fields (`AXSecureTextField`), honors per-application exclusions (`Settings → Exceptions`), acts as a complete no-op when disabled, and never logs user text, passwords, or clipboard contents.
- **Customizable global shortcut** defaulting to `⌥X`, with rollback to the previous active shortcut if registration fails.
- **Menu bar utility and Settings UI** with enable/disable toggle, manual **Fix Text** action, Accessibility permission status, shortcut recorder, and application exception picker.
- **Launch at Login** integration via `SMAppService` and local JSON configuration at `~/Library/Application Support/Henge/config.json` with automatic backup recovery for corrupt files.
- **Universal macOS builds (`arm64` + `x86_64`)** and packaging scripts (`scripts/build.sh`, `scripts/package.sh`) with `SHA256SUMS.txt` verification and `--probe` CLI diagnostics (`HengeProbeRunner`).

[Unreleased]: https://github.com/413d/henge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/413d/henge/releases/tag/v0.1.0
