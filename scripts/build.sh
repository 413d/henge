#!/usr/bin/env bash
# Unified build and bundle script for Henge.app.
# Builds native (host architecture) or universal (arm64 + x86_64),
# creates the macOS .app bundle, materializes Info.plist, signs ad-hoc,
# verifies integrity, and optionally installs to ~/Applications or a custom path.
#
# Usage:
#   scripts/build.sh [native|universal] [--install [TARGET_DIR]] [--debug|--release]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

BUNDLE_ID="io.github.henge.Henge"
APP_NAME="Henge"
APP_VERSION="${HENGE_VERSION:-0.1.0}"
BUILD_NUMBER="${HENGE_BUILD_NUMBER:-2}"
MIN_MACOS="13.0"

TARGET="native"
CONFIGURATION="release"
INSTALL=false
INSTALL_DIR="${HOME}/Applications"

while [[ $# -gt 0 ]]; do
    case "$1" in
        native|universal)
            TARGET="$1"
            shift
            ;;
        --debug)
            CONFIGURATION="debug"
            shift
            ;;
        --release)
            CONFIGURATION="release"
            shift
            ;;
        --install)
            INSTALL=true
            shift
            if [[ $# -gt 0 && ! "$1" =~ ^-- ]]; then
                INSTALL_DIR="$1"
                shift
            fi
            ;;
        -h|--help)
            echo "Usage: $0 [native|universal] [--install [TARGET_DIR]] [--debug|--release]"
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            echo "Usage: $0 [native|universal] [--install [TARGET_DIR]] [--debug|--release]" >&2
            exit 2
            ;;
    esac
done

if [[ "${TARGET}" == "universal" ]]; then
    APP_DIR="build/universal/${APP_NAME}.app"
    ARCHITECTURES=("arm64" "x86_64")
else
    APP_DIR="build/${APP_NAME}.app"
    ARCHITECTURES=("$(uname -m)")
fi

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

    if [[ "${TARGET}" == "universal" ]]; then
        lipo "$exe" -verify_arch arm64 x86_64 \
            || { echo "error: executable is not universal arm64 + x86_64" >&2; return 1; }
        echo "verify: universal architecture OK"
    fi

    codesign --verify --deep --strict --verbose=2 "$app"
    local sig_info
    sig_info="$(codesign -dv "$app" 2>&1)"
    grep -q 'Signature=adhoc' <<<"$sig_info" \
        || { echo "error: bundle is not ad-hoc signed" >&2; return 1; }
    echo "verify: ad-hoc signature OK"
}

BINARIES=()
if [[ "${TARGET}" == "universal" ]]; then
    for arch in "${ARCHITECTURES[@]}"; do
        echo "==> swift build -c ${CONFIGURATION} --triple ${arch}-apple-macosx${MIN_MACOS}"
        swift build -c "${CONFIGURATION}" --triple "${arch}-apple-macosx${MIN_MACOS}"
        bin_dir="$(swift build -c "${CONFIGURATION}" --triple "${arch}-apple-macosx${MIN_MACOS}" --show-bin-path)"
        BINARIES+=("${bin_dir}/${APP_NAME}")
    done
else
    echo "==> swift build -c ${CONFIGURATION}"
    swift build -c "${CONFIGURATION}"
    bin_dir="$(swift build -c "${CONFIGURATION}" --show-bin-path)"
    BINARIES+=("${bin_dir}/${APP_NAME}")
fi

for bin in "${BINARIES[@]}"; do
    if [[ ! -x "${bin}" ]]; then
        echo "error: built binary not found at ${bin}" >&2
        exit 1
    fi
done

echo "==> Assembling ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"

if [[ ${#BINARIES[@]} -eq 1 ]]; then
    cp "${BINARIES[0]}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
else
    echo "==> Creating universal binary with lipo"
    lipo -create "${BINARIES[@]}" -output "${APP_DIR}/Contents/MacOS/${APP_NAME}"
fi
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

echo "==> Ready: ${APP_DIR}"
lipo -info "${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [[ "${INSTALL}" == true ]]; then
    echo "==> Installing to ${INSTALL_DIR}/${APP_NAME}.app"
    mkdir -p "${INSTALL_DIR}"
    pkill -x "${APP_NAME}" 2>/dev/null || true
    rm -rf "${INSTALL_DIR}/${APP_NAME}.app"
    ditto "${APP_DIR}" "${INSTALL_DIR}/${APP_NAME}.app"
    echo "Installed to ${INSTALL_DIR}/${APP_NAME}.app."
    echo "NOTE: Ad-hoc signature resets the Accessibility grant."
    echo "Re-enable it if needed: System Settings → Privacy & Security → Accessibility → ${APP_NAME}"
    echo "Launch with: open '${INSTALL_DIR}/${APP_NAME}.app'"
    exit 0
fi

echo
echo "To install locally, run:"
echo "  $0 --install"
echo "  # or to a custom path (e.g. /Applications):"
echo "  $0 --install /Applications"
