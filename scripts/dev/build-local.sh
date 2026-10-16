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
    local lint_out
    lint_out="$(plutil -lint "$plist")" \
        || { echo "error: Info.plist lint failed: ${lint_out}" >&2; return 1; }
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
    local sig_info
    sig_info="$(codesign -dv "$app" 2>&1)"
    grep -q 'Signature=adhoc' <<<"$sig_info" \
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
lint_out="$(plutil -lint "${PLIST}")" \
    || { echo "error: materialized Info.plist lint failed: ${lint_out}" >&2; exit 1; }

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
