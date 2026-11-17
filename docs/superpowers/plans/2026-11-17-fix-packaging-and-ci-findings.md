# Packaging & CI Audit Findings Fix Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to execute this plan task-by-task.

**Goal:** Address all P1 and P2 findings from the Senior macOS/Swift Release Reviewer audit regarding `scripts/build.sh`, `scripts/package.sh`, `.github/workflows/ci.yml`, and `README.md`.

**Branch:** `fix/packaging-and-ci-audit-findings`

## Findings Addressed
- Finding 1: Copy `App/HengeMenuBar.png` to `Contents/Resources/` in `scripts/build.sh`.
- Finding 2: Document Gatekeeper quarantine removal (`xattr -cr`) in `README.md`.
- Finding 3: Fix CLI argument parsing in `scripts/build.sh` so `--install` does not greedily consume `native`/`universal`.
- Finding 4: Replace `sed` with `plutil -replace` for `Info.plist` materialization in `scripts/build.sh`.
- Finding 5: Add graceful wait loop for `pkill` in `scripts/build.sh` before `rm -rf` and `ditto`.
- Finding 6: Add Rosetta 2 `arch -x86_64 swift test` in `.github/workflows/ci.yml`.
- Finding 7: Verify extracted zip archive in `.github/workflows/ci.yml`.
- Finding 8: Support custom `HENGE_SIGNING_IDENTITY` (defaulting to ad-hoc `-`) in `scripts/build.sh`.
- Finding 9: Avoid redundant `swift build --show-bin-path` in `scripts/build.sh`.
- Finding 10: Ensure license and packaging staging are clean in `scripts/package.sh`.

---

### Task 1: Fix `scripts/build.sh` (Findings 1, 3, 4, 5, 8, 9)

**Files:**
- Modify: `scripts/build.sh`

- [x] **Step 1: Update argument parsing**
  Ensure `--install` does not capture positional targets `native` or `universal`.
- [x] **Step 2: Optimize binary path retrieval**
  Cache `bin_dir` per build configuration.
- [x] **Step 3: Copy menu bar icon asset**
  Copy `App/HengeMenuBar.png` to `${APP_DIR}/Contents/Resources/HengeMenuBar.png` if it exists.
- [x] **Step 4: Use `plutil -replace` for Info.plist**
  Copy `App/Info.plist` and use `plutil -replace` for `CFBundleIdentifier`, `CFBundleShortVersionString`, `CFBundleVersion`, `CFBundleExecutable`.
- [x] **Step 5: Support `HENGE_SIGNING_IDENTITY`**
  Default to `-`, but allow local certificate identity.
- [x] **Step 6: Add process termination wait loop**
  When stopping running instance, loop up to 2 seconds with `sleep 0.1` checking `pgrep -x "${APP_NAME}"`, falling back to `pkill -9`.
- [x] **Step 7: Test `scripts/build.sh` locally**
  Run `bash -n scripts/build.sh`, `./scripts/build.sh native`, and check `Contents/Resources/HengeMenuBar.png`.

---

### Task 2: Update `scripts/package.sh` (Finding 10)

**Files:**
- Modify: `scripts/package.sh`

- [x] **Step 1: Check and clean packaging logic**
  Ensure staging directory and archive generation remain reliable and clean.
- [x] **Step 2: Test `scripts/package.sh` locally**
  Run `./scripts/package.sh` and verify archive contents with `unzip -l dist/Henge-universal.zip`.

---

### Task 3: Enhance `.github/workflows/ci.yml` (Findings 6, 7)

**Files:**
- Modify: `.github/workflows/ci.yml`

- [x] **Step 1: Add Rosetta 2 testing in CI**
  Add step `Run tests (x86_64 via Rosetta)` using `arch -x86_64 swift test`.
- [x] **Step 2: Add extracted archive verification in CI**
  In `package` job, extract `dist/Henge-universal.zip` to a temp directory and run `codesign --verify` and `lipo -verify_arch` on the extracted `.app`.
- [x] **Step 3: Validate YAML**
  Verify YAML syntax with ruby / parser.

---

### Task 4: Documentation & Backlog Sync (Finding 2)

**Files:**
- Modify: `README.md`
- Modify: `~/brain/Projects/henge/engineering-backlog.md`

- [x] **Step 1: Add Gatekeeper instructions to `README.md`**
  Add note explaining macOS 15 Gatekeeper quarantine and how to run `xattr -cr` on downloaded `.app`.
- [x] **Step 2: Document `HENGE_SIGNING_IDENTITY` in `README.md`**
  Mention how a self-signed certificate in Keychain preserves Accessibility permissions across builds.
- [x] **Step 3: Update GBrain backlog**
  Update Timeline with audit fixes.
