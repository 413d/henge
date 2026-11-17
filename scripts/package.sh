#!/usr/bin/env bash
# Package universal Henge.app into a distributable zip archive with SHA-256 checksums.
#
# Usage:
#   scripts/package.sh
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ $# -gt 0 ]]; then
    case "$1" in
        -h|--help)
            echo "Usage: $0"
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            echo "Usage: $0" >&2
            exit 2
            ;;
    esac
fi

APP_NAME="Henge"
UNIVERSAL_APP="build/universal/${APP_NAME}.app"
DIST_DIR="dist"
ARCHIVE_NAME="${APP_NAME}-universal.zip"

echo "==> Building universal application bundle"
"${REPO_ROOT}/scripts/build.sh" universal --release

if [[ ! -d "${UNIVERSAL_APP}" ]]; then
    echo "error: universal app bundle not found at ${UNIVERSAL_APP}" >&2
    exit 1
fi

echo "==> Packaging into ${DIST_DIR}/${ARCHIVE_NAME}"
rm -rf "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

ditto -c -k --norsrc --noextattr --noacl --keepParent "${UNIVERSAL_APP}" "${DIST_DIR}/${ARCHIVE_NAME}"

if [[ -f "${REPO_ROOT}/LICENSE" ]]; then
    cp "${REPO_ROOT}/LICENSE" "${DIST_DIR}/LICENSE.txt"
elif [[ -f "${REPO_ROOT}/LICENSE.txt" ]]; then
    cp "${REPO_ROOT}/LICENSE.txt" "${DIST_DIR}/LICENSE.txt"
fi

echo "==> Generating SHA256 checksums"
(
    cd "${DIST_DIR}"
    shasum -a 256 "${ARCHIVE_NAME}" > SHA256SUMS.txt
    shasum -a 256 -c SHA256SUMS.txt
)

echo
echo "==> Package ready:"
ls -lh "${DIST_DIR}"
cat "${DIST_DIR}/SHA256SUMS.txt"
