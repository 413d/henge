#!/usr/bin/env bash
# Package universal Henge.app into a distributable zip archive with SHA-256 checksums.
#
# Usage:
#   scripts/package.sh [--archive-name NAME.zip]
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

APP_NAME="Henge"
ARCHIVE_NAME="${HENGE_ARCHIVE_NAME:-${APP_NAME}-universal.zip}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --archive-name)
            if [[ $# -lt 2 || -z "$2" ]]; then
                echo "error: --archive-name requires a non-empty filename" >&2
                exit 2
            fi
            ARCHIVE_NAME="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--archive-name NAME.zip]"
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            echo "Usage: $0 [--archive-name NAME.zip]" >&2
            exit 2
            ;;
    esac
done

if [[ "${ARCHIVE_NAME}" == */* || "${ARCHIVE_NAME}" == *".."* || ! "${ARCHIVE_NAME}" =~ \.zip$ ]]; then
    echo "error: invalid archive name '${ARCHIVE_NAME}' (must be a plain .zip filename)" >&2
    exit 2
fi

UNIVERSAL_APP="build/universal/${APP_NAME}.app"
DIST_DIR="dist"

echo "==> Building universal application bundle"
"${REPO_ROOT}/scripts/build.sh" universal --release

if [[ ! -d "${UNIVERSAL_APP}" ]]; then
    echo "error: universal app bundle not found at ${UNIVERSAL_APP}" >&2
    exit 1
fi

echo "==> Packaging into ${DIST_DIR}/${ARCHIVE_NAME}"
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/${ARCHIVE_NAME}" \
      "${DIST_DIR}/SHA256SUMS.txt" \
      "${DIST_DIR}/LICENSE.txt"

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
