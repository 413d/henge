# Local Bundle Hardening — Design (2026-10-16)

## Context

`scripts/dev/build-local.sh` already implements the full local `.app` flow
(swift release build → bundle layout → Info.plist materialization → binary + icon
copy → ad-hoc `codesign`). Verified working: `build/Henge.app` passes
`codesign --verify --deep --strict`, `plutil -lint`, and has the executable bit.

Gaps found during review:

1. No post-signature verification inside the script.
2. Icon copy is mandatory — build fails if `App/Henge.icns` is missing, although
   the icon is optional per requirements.
3. Executable bit only inherited from `cp`; no explicit `chmod +x`.
4. Install is printed as manual commands only; no `--install` flag.
5. Dead empty `App/Resources/` directory.

## Decisions

- Extend the existing script (approach A). Verification lives in a local
  `verify_bundle()` function so it can be extracted later if needed.
- CLI: `scripts/dev/build-local.sh [release|debug] [--install]`.
  `--install` copies to `/Applications` via `rm -rf` + `ditto` only — no `open`,
  no launch (user decision).
- Icon: copy when present, warn and continue when absent.
- Explicit `chmod +x` on `Contents/MacOS/Henge`.
- `verify_bundle()` checks: executable bit, `plutil -lint`, required Info.plist
  keys non-empty (`CFBundleName`, `CFBundleIdentifier`, `CFBundleExecutable`,
  `CFBundleInfoDictionaryVersion`, `CFBundlePackageType`,
  `CFBundleShortVersionString`), identifier equals `io.github.henge.Henge`,
  package type `APPL`, `codesign --verify --deep --strict`, ad-hoc signature
  present. Any failure aborts (`set -euo pipefail`).
- Docs: README local-build section gains the `--install` example; GBrain
  `projects/henge/engineering-backlog` gets a timeline entry.

## Out of scope

- `scripts/release/create-rc.sh` (Developer ID + notarization) — untouched.
- Architecture: Intel x86_64-only build is correct for this machine.
- Launch-on-install (`open`), `spctl` assessment (not applicable to ad-hoc),
  unrelated uncommitted workspace changes.

## Identity constants

- Bundle ID: `io.github.henge.Henge`, name/executable: `Henge`,
  version `0.1.0`, build `2`.
