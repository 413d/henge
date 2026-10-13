#!/bin/bash

# Build, sign, notarize, staple, and verify the Henge macOS Release Candidate.
# Credentials are supplied by the local environment/Keychain and are never saved here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

fail() {
    printf 'Release build stopped: %s\n' "$1" >&2
    exit 1
}

: "${HENGE_TEAM_ID:?Set HENGE_TEAM_ID to the Apple Developer Team ID.}"
: "${HENGE_SIGNING_IDENTITY:?Set HENGE_SIGNING_IDENTITY to the exact Developer ID Application identity.}"
: "${HENGE_NOTARY_PROFILE:?Set HENGE_NOTARY_PROFILE to an existing notarytool Keychain profile name.}"

VERSION="${HENGE_VERSION:-0.1.0}"
BUILD_NUMBER="${HENGE_BUILD_NUMBER:-2}"
RC_NUMBER="${HENGE_RC_NUMBER:-1}"
RELEASE_DIR="$REPO_ROOT/.build/release"
ARCHIVE_PATH="$RELEASE_DIR/Henge-$VERSION-rc.$RC_NUMBER.xcarchive"
APP_PATH="$ARCHIVE_PATH/Products/Applications/Henge.app"
DMG_PATH="$RELEASE_DIR/Henge-$VERSION-rc.$RC_NUMBER.dmg"
SUBMISSION_PATH="$RELEASE_DIR/Henge-$VERSION-rc.$RC_NUMBER-notary.json"
NOTARY_LOG_PATH="$RELEASE_DIR/Henge-$VERSION-rc.$RC_NUMBER-notary-log.json"

for tool in xcodebuild xcrun codesign security lipo hdiutil spctl shasum; do
    command -v "$tool" >/dev/null 2>&1 || fail "Required Apple tool is unavailable: $tool"
done

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "HENGE_VERSION must be a numeric version such as 0.1.0."
[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]] || fail "HENGE_BUILD_NUMBER must be an integer."
[[ "$RC_NUMBER" =~ ^[0-9]+$ ]] || fail "HENGE_RC_NUMBER must be an integer."

IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
printf '%s\n' "$IDENTITIES" | grep -F "$HENGE_SIGNING_IDENTITY" | grep -F "$HENGE_TEAM_ID" >/dev/null \
    || fail "The requested Developer ID identity was not found in the local Keychain."

mkdir -p "$RELEASE_DIR"
[[ ! -e "$ARCHIVE_PATH" ]] || fail "Archive already exists; move it aside before rebuilding: $ARCHIVE_PATH"
[[ ! -e "$DMG_PATH" ]] || fail "DMG already exists; move it aside before rebuilding: $DMG_PATH"

xcodebuild \
    -project Henge.xcodeproj \
    -scheme Henge \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    DEVELOPMENT_TEAM="$HENGE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$HENGE_SIGNING_IDENTITY" \
    ENABLE_HARDENED_RUNTIME=YES \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    archive

[[ -d "$APP_PATH" ]] || fail "Xcode archive did not contain Henge.app."
APP_EXECUTABLE="$APP_PATH/Contents/MacOS/Henge"
[[ -f "$APP_EXECUTABLE" ]] || fail "Henge executable is missing from the archive."

APP_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
[[ "$APP_BUNDLE_ID" == 'io.github.henge.Henge' ]] || fail "Unexpected bundle identifier: $APP_BUNDLE_ID"
lipo -verify_arch arm64 x86_64 "$APP_EXECUTABLE" || fail "The app is not a universal arm64 + x86_64 binary."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

ENTITLEMENTS="$(codesign -d --entitlements :- "$APP_PATH" 2>/dev/null || true)"
if printf '%s' "$ENTITLEMENTS" | grep -q 'com.apple.security.get-task-allow'; then
    fail "The release app contains get-task-allow; inspect and remove the debug entitlement."
fi

STAGING_DIR="$(mktemp -d "$RELEASE_DIR/staging.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

ditto "$APP_PATH" "$STAGING_DIR/Henge.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create -volname Henge -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
codesign --force --sign "$HENGE_SIGNING_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

if ! xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$HENGE_NOTARY_PROFILE" \
    --wait \
    --output-format json >"$SUBMISSION_PATH" 2>&1; then
    cat "$SUBMISSION_PATH" >&2
    fail "Apple notarization submission failed. See the output above."
fi

if ! grep -Eq '"status"[[:space:]]*:[[:space:]]*"Accepted"' "$SUBMISSION_PATH"; then
    cat "$SUBMISSION_PATH" >&2
    JOB_ID="$(sed -n 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SUBMISSION_PATH" | head -n 1)"
    if [[ -n "$JOB_ID" ]]; then
        xcrun notarytool log "$JOB_ID" --keychain-profile "$HENGE_NOTARY_PROFILE" "$NOTARY_LOG_PATH" || true
        printf 'Notary log saved at: %s\n' "$NOTARY_LOG_PATH" >&2
    fi
    fail "Apple did not accept this notarization submission. Do not distribute the DMG."
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"

printf '\nRelease Candidate verified locally:\n'
printf 'App: %s\nDMG: %s\n' "$APP_PATH" "$DMG_PATH"
shasum -a 256 "$DMG_PATH"
