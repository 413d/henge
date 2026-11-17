# App Packaging and GitHub Actions CI/CD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create unified macOS `.app` packaging scripts (native & universal arm64+x86_64) with ad-hoc signing, local installation to `~/Applications`, release zip packaging with SHA-256 sums, and a GitHub Actions CI workflow to automate testing and release artifact creation on push to `main`.

**Architecture:** Pure bash scripts wrapping Swift CLI (`swift build`, `swift test`, `lipo`, `codesign`, `plutil`) producing a standard macOS app bundle hierarchy (`Contents/MacOS`, `Contents/Resources`, `Contents/Info.plist`), ad-hoc signed and verified. A declarative GitHub Actions workflow runs on macOS runner, runs unit tests, builds the universal bundle, verifies checksums, and uploads the artifact.

**Tech Stack:** Bash, Swift 6.0+, macOS ApplicationServices, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-17-app-packaging-and-ci-design.md`

## Global Constraints

- No third-party build dependencies (no xcbeautify, no fastlane, pure native Apple/Swift CLI tools).
- macOS 13+ deployment target (`arm64-apple-macosx13.0` and `x86_64-apple-macosx13.0`).
- Ad-hoc codesign (`codesign --force --deep --sign -`).
- App bundle identifier: `io.github.henge.Henge`.
- Executable name: `Henge`.
- Installation target defaults to `$HOME/Applications`, supporting custom paths like `/Applications`.
- Update GBrain documentation per `AGENTS.md`.

## Review Focus

1. Missing `~/Applications` directory: install step must run `mkdir -p "$target_dir"` and handle user write permissions gracefully.
2. Architecture verification: universal binary must contain both `arm64` and `x86_64` verified with `xcrun lipo -verify_arch`.
3. Info.plist integrity: all mandatory keys must be present and validated via `plutil -lint`.
4. Ad-hoc codesign validity: verified with `codesign --verify --deep --strict`.
5. Missing icon resilience: if `App/Henge.icns` is missing, script warns and succeeds without failing the build.

---

### Task 1: Create `scripts/build.sh` with Native & Universal Support and User Installation

**Files:**
- Create: `scripts/build.sh`
- Modify: `scripts/dev/build-local.sh` (delegate to `scripts/build.sh`)
- Test: manual execution with `scripts/build.sh native` and `scripts/build.sh universal`

**Interfaces:**
- Consumes: `App/Info.plist`, `App/Henge.icns`, `Sources/`
- Produces: `build/Henge.app` (native) and `build/universal/Henge.app` (universal)

- [ ] **Step 1: Write `scripts/build.sh`**

Implement bash script supporting:
- Arguments: `[native|universal] [--install [DIR]] [--debug|--release]`
- Multi-architecture builds using `swift build -c <config> --triple <arch>-apple-macosx13.0`
- Mach-O universal fat binary creation via `lipo -create` when `universal` is selected
- Bundle layout: `Contents/MacOS`, `Contents/Resources`, `Contents/Info.plist`
- `sed` replacement of variables in `App/Info.plist`
- Copying `App/Henge.icns` if present to `Contents/Resources/Henge.icns`
- `chmod +x` on the executable
- Ad-hoc signature `codesign --force --deep --sign -`
- Verification step: `codesign --verify --deep --strict`, `plutil -lint`, non-empty required plist keys, lipo arch check
- `--install` logic: installs to `${TARGET_DIR:-$HOME/Applications}`, with `mkdir -p`, and `ditto`

- [ ] **Step 2: Make `scripts/build.sh` executable and test syntax**

Run: `chmod +x scripts/build.sh && bash -n scripts/build.sh`
Expected: PASS with 0 exit code

- [ ] **Step 3: Run `scripts/build.sh native` and verify bundle**

Run: `./scripts/build.sh native`
Expected: Successful build in `build/Henge.app`, passing verification

- [ ] **Step 4: Run `scripts/build.sh universal` and verify universal binary**

Run: `./scripts/build.sh universal`
Expected: Successful build in `build/universal/Henge.app`, `lipo -info` showing `arm64` and `x86_64`

- [ ] **Step 5: Update `scripts/dev/build-local.sh` to delegate to `scripts/build.sh`**

Keep backward compatibility for any existing invocation of `scripts/dev/build-local.sh`.

- [ ] **Step 6: Commit Task 1**

```bash
git add scripts/build.sh scripts/dev/build-local.sh
git commit -m "feat(build): add unified build.sh supporting native and universal app bundles"
```

---

### Task 2: Create `scripts/package.sh` for Release Zip and Checksums

**Files:**
- Create: `scripts/package.sh`
- Test: manual execution with `./scripts/package.sh`

**Interfaces:**
- Consumes: `scripts/build.sh universal`, `LICENSE`
- Produces: `dist/Henge-universal.zip`, `dist/SHA256SUMS.txt`

- [ ] **Step 1: Write `scripts/package.sh`**

Implement bash script:
- Invokes `./scripts/build.sh universal`
- Prepares staging directory with `Henge.app`, `LICENSE`
- Creates `dist/Henge-universal.zip` using `ditto -c -k --norsrc --noextattr --noacl --keepParent`
- Generates `dist/SHA256SUMS.txt` via `shasum -a 256`
- Verifies checksums

- [ ] **Step 2: Make `scripts/package.sh` executable and test syntax**

Run: `chmod +x scripts/package.sh && bash -n scripts/package.sh`
Expected: PASS with 0 exit code

- [ ] **Step 3: Run `./scripts/package.sh` and verify outputs**

Run: `./scripts/package.sh`
Expected: `dist/Henge-universal.zip` and `dist/SHA256SUMS.txt` created, checksum passes `shasum -a 256 -c SHA256SUMS.txt`

- [ ] **Step 4: Commit Task 2**

```bash
git add scripts/package.sh
git commit -m "feat(package): add package.sh to create universal release zip and checksums"
```

---

### Task 3: Create GitHub Actions Workflow `.github/workflows/ci.yml`

**Files:**
- Create: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: `swift test`, `scripts/build.sh`, `scripts/package.sh`
- Produces: GitHub Actions CI run, uploaded artifact `henge-macos-universal` containing `dist/Henge-universal.zip` and `dist/SHA256SUMS.txt`

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

Workflow specification:
- Name: `CI`
- Triggers: `push` on `branches: [main]`, `pull_request`, `workflow_dispatch`
- Permissions: `contents: read`
- Runner: `macos-15` (or `macos-14`)
- Job 1: `test` (runs `swift test`, validates shell scripts with `bash -n`, lints `App/Info.plist`)
- Job 2: `build-and-package` (runs `./scripts/package.sh`, verifies checksums, uploads artifacts via `actions/upload-artifact@v4`)

- [ ] **Step 2: Validate workflow syntax and references**

Verify yaml formatting and step structure.

- [ ] **Step 3: Commit Task 3**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add GitHub Actions workflow for test, build, and packaging"
```

---

### Task 4: Documentation & GBrain Sync

**Files:**
- Modify: `README.md`
- Modify: `~/brain/Projects/henge/engineering-backlog.md`

**Interfaces:**
- Consumes: updated build scripts and workflow details
- Produces: updated documentation in repo and GBrain

- [ ] **Step 1: Update `README.md`**

Add instructions for:
- `./scripts/build.sh` (native build)
- `./scripts/build.sh --install` (install to `~/Applications`)
- `./scripts/build.sh universal` (universal build)
- `./scripts/package.sh` (distributable zip)

- [ ] **Step 2: Update GBrain backlog**

Add a summary entry in `~/brain/Projects/henge/engineering-backlog.md` documenting the unified build scripts and CI/CD workflow.

- [ ] **Step 3: Run full verification**

Run tests (`swift test`), verify clean git status, verify script runs.

- [ ] **Step 4: Commit Task 4**

```bash
git add README.md
git commit -m "docs: document build scripts and packaging workflow"
```
