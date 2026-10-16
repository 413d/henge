# Local Bundle Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Доработать `scripts/dev/build-local.sh`: строгая верификация бандла после подписи, явный `chmod +x`, опциональная иконка, флаг `--install`, плюс README-доки.

**Architecture:** Одна точка изменений — dev-скрипт сборки; верификация оформлена как функция `verify_bundle` внутри него (при желании выносится в отдельный скрипт позже). Release-путь `create-rc.sh` не трогается.

**Tech Stack:** Bash (`set -euo pipefail`), `plutil`, `PlistBuddy`, `codesign`, `ditto`.

## Global Constraints

- Bundle ID: `io.github.henge.Henge`; имя: `Henge`; версия `0.1.0`, build `2`
- Аппарат Intel (x86_64) — архитектуру не менять
- Ad-hoc подпись (`codesign --force --deep --sign -`), без Developer ID/notarization
- Никаких зависимостей вне нативных Apple-тулов; README и GBrain-доки обновляются вместе со скриптом (AGENTS.md)
- Коммитить только файлы задач; несвязанные незакоммиченные изменения рабочего дерева не трогать

---

### Task 1: Доработать `scripts/dev/build-local.sh`

**Files:**
- Modify: `scripts/dev/build-local.sh` (45 строк → ~95)

**Interfaces:**
- Produces: CLI `scripts/dev/build-local.sh [release|debug] [--install]`; функция `verify_bundle <app_path>` (код возврата 0/1, печатает `verify: <проверка> OK`); константы `BUNDLE_ID`, `APP_VERSION`, `BUILD_NUMBER`

- [ ] **Step 1: Заменить тело скрипта** на:

```bash
#!/usr/bin/env bash
# Local (unsigned / ad-hoc) build of Henge.app for personal use.
# No Developer ID, no notarization — suitable only for installing on this machine.
# Usage: scripts/dev/build-local.sh [release|debug] [--install]
set -euo pipefail
cd "$(dirname "$0")/../.."

BUNDLE_ID="io.github.henge.Henge"
APP_NAME="Henge"
APP_VERSION="0.1.0"
BUILD_NUMBER="2"
APP_DIR="build/${APP_NAME}.app"

CONFIGURATION="release"
INSTALL=false
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=true ;;
        release|debug) CONFIGURATION="$arg" ;;
        *) echo "usage: $0 [release|debug] [--install]" >&2; exit 2 ;;
    esac
done

verify_bundle() {
    local app="$1"
    local plist="${app}/Contents/Info.plist"
    local exe="${app}/Contents/MacOS/${APP_NAME}"

    [[ -x "$exe" ]] || { echo "error: missing or non-executable: $exe" >&2; return 1; }
    echo "verify: executable bit OK"
    plutil -lint "$plist" >/dev/null
    echo "verify: Info.plist lint OK"

    local key actual
    for key in CFBundleName CFBundleIdentifier CFBundleExecutable \
               CFBundleInfoDictionaryVersion CFBundlePackageType \
               CFBundleShortVersionString; do
        actual="$(/usr/libexec/PlistBuddy -c "Print :${key}" "$plist" 2>/dev/null)" \
            || { echo "error: Info.plist missing key ${key}" >&2; return 1; }
        [[ -n "$actual" ]] || { echo "error: Info.plist key ${key} is empty" >&2; return 1; }
    done
    echo "verify: required Info.plist keys OK"

    actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
    [[ "$actual" == "$BUNDLE_ID" ]] \
        || { echo "error: CFBundleIdentifier '$actual' != '$BUNDLE_ID'" >&2; return 1; }
    actual="$(/usr/libexec/PlistBuddy -c 'Print :CFBundlePackageType' "$plist")"
    [[ "$actual" == "APPL" ]] \
        || { echo "error: CFBundlePackageType '$actual' != 'APPL'" >&2; return 1; }
    echo "verify: bundle identity OK"

    if [[ -f "${app}/Contents/Resources/${APP_NAME}.icns" ]]; then
        echo "verify: icon present OK"
    fi

    codesign --verify --deep --strict --verbose=2 "$app"
    codesign -dv "$app" 2>&1 | grep -q 'Signature=adhoc' \
        || { echo "error: bundle is not ad-hoc signed" >&2; return 1; }
    echo "verify: ad-hoc signature OK"
}

echo "==> swift build -c ${CONFIGURATION}"
swift build -c "${CONFIGURATION}"

BIN_PATH="$(swift build -c "${CONFIGURATION}" --show-bin-path)/${APP_NAME}"
if [[ ! -x "${BIN_PATH}" ]]; then
    echo "error: built binary not found at ${BIN_PATH}" >&2
    exit 1
fi

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [[ -f App/${APP_NAME}.icns ]]; then
    cp "App/${APP_NAME}.icns" "${APP_DIR}/Contents/Resources/${APP_NAME}.icns"
else
    echo "warning: App/${APP_NAME}.icns not found — skipping icon" >&2
fi

PLIST="${APP_DIR}/Contents/Info.plist"
sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
    -e "s/\$(MARKETING_VERSION)/${APP_VERSION}/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/${BUILD_NUMBER}/g" \
    -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
    App/Info.plist > "${PLIST}"
plutil -lint "${PLIST}" >/dev/null

echo "==> Ad-hoc codesign"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> Verify"
verify_bundle "${APP_DIR}"

if [[ "${INSTALL}" == true ]]; then
    echo "==> Install to /Applications"
    rm -rf "/Applications/${APP_NAME}.app"
    ditto "${APP_DIR}" "/Applications/${APP_NAME}.app"
    echo "Installed. NOTE: ad-hoc signature resets the Accessibility grant —"
    echo "re-enable it: System Settings → Privacy & Security → Accessibility → ${APP_NAME}"
    exit 0
fi

echo "==> Done: ${APP_DIR}"
echo
echo "Install with:"
echo "  $0 --install"
echo "  # or manually:"
echo "  rm -rf /Applications/${APP_NAME}.app && ditto '${APP_DIR}' /Applications/${APP_NAME}.app"
echo "  open /Applications/${APP_NAME}.app"
echo
echo "Then grant Accessibility:"
echo "  System Settings → Privacy & Security → Accessibility → enable ${APP_NAME}"
```

- [ ] **Step 2: Синтаксис-проверка**

Run: `bash -n scripts/dev/build-local.sh`
Expected: без вывода, код 0

- [ ] **Step 3: Прогон сборки** (shell: TDD неприменим; верификация и есть тест)

Run: `./scripts/dev/build-local.sh`
Expected: `==> Verify`, далее все строки `verify: … OK`, финально `==> Done: build/Henge.app`

- [ ] **Step 4: Независимая проверка результата**

Run:
```bash
codesign --verify --deep --strict --verbose=2 build/Henge.app && \
plutil -lint build/Henge.app/Contents/Info.plist && \
ls -l build/Henge.app/Contents/MacOS/Henge && \
file build/Henge.app/Contents/MacOS/Henge
```
Expected: `valid on disk` / `satisfies its Designated Requirement`, `OK`, `-rwxr-xr-x`, `Mach-O 64-bit executable x86_64`

- [ ] **Step 5: Проверка флага `--install`**

Run: `./scripts/dev/build-local.sh --install`
Expected: `==> Install to /Applications`, `Installed. NOTE: … Accessibility …`; затем `test -d /Applications/Henge.app`

- [ ] **Step 6: Негативный кейс аргументов**

Run: `./scripts/dev/build-local.sh --bogus; echo exit=$?`
Expected: `usage: … [release|debug] [--install]`, `exit=2`

- [ ] **Step 7: Commit**

```bash
git add scripts/dev/build-local.sh
git commit -m "build: harden local bundle script with verification and --install"
```

---

### Task 2: README + гигиена + GBrain-доки

**Files:**
- Modify: `README.md` (секция Local build, строки 42–55)
- Delete: пустая директория `App/Resources/` (untracked)
- GBrain: `projects/henge/engineering-backlog` (timeline-запись)

**Interfaces:**
- Consumes: CLI из Task 1 — `scripts/dev/build-local.sh --install`

- [ ] **Step 1: README** — в блоке Local build заменить команды на:

```bash
./scripts/dev/build-local.sh --install   # release build → build/Henge.app (ad-hoc signed) → /Applications/Henge.app
open /Applications/Henge.app             # launch from Finder
```
и оставить существующий абзац про сброс Accessibility-гранта.

- [ ] **Step 2: Гигиена** — `rmdir App/Resources` (если не пустая — не удалять, сообщить).

- [ ] **Step 3: GBrain** — добавить timeline-запись в `projects/henge/engineering-backlog` (get_page → add_timeline_entry): hardened `build-local.sh` — post-sign verify (plist keys, identity, ad-hoc), explicit chmod, optional icon, `--install`.

- [ ] **Step 4: Проверка**

Run: `grep -n -- '--install' README.md`
Expected: совпадение в секции Local build

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: document build-local.sh --install flow"
```
