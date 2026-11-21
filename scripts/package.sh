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

UNIVERSAL_APP="${HENGE_PACKAGE_APP_PATH:-build/universal/${APP_NAME}.app}"
DIST_DIR="${HENGE_DIST_DIR:-dist}"
SKIP_BUILD="${HENGE_PACKAGE_SKIP_BUILD:-false}"
INSTALL_GUIDE="${REPO_ROOT}/App/INSTALL.txt"

if [[ ! -f "${INSTALL_GUIDE}" ]]; then
    echo "error: installation guide not found at ${INSTALL_GUIDE}" >&2
    exit 1
fi

if [[ "${SKIP_BUILD}" != "true" ]]; then
    echo "==> Building universal application bundle"
    "${REPO_ROOT}/scripts/build.sh" universal --release
fi

if [[ ! -d "${UNIVERSAL_APP}" ]]; then
    echo "error: universal app bundle not found at ${UNIVERSAL_APP}" >&2
    exit 1
fi

STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/henge-package.XXXXXX")"
cleanup() {
    rm -rf "${STAGE_ROOT}"
}
trap cleanup EXIT

STAGE_DIR="${STAGE_ROOT}/archive"
VERIFY_DIR="${STAGE_ROOT}/verify"
mkdir -p "${STAGE_DIR}" "${VERIFY_DIR}"

ditto --norsrc --noextattr --noacl "${UNIVERSAL_APP}" "${STAGE_DIR}/${APP_NAME}.app"
cp "${INSTALL_GUIDE}" "${STAGE_DIR}/INSTALL.txt"
xattr -c "${STAGE_DIR}/INSTALL.txt" 2>/dev/null || true

echo "==> Packaging into ${DIST_DIR}/${ARCHIVE_NAME}"
mkdir -p "${DIST_DIR}"
rm -f "${DIST_DIR}/${ARCHIVE_NAME}" \
      "${DIST_DIR}/SHA256SUMS.txt" \
      "${DIST_DIR}/LICENSE.txt" \
      "${DIST_DIR}/INSTALL.txt"

ditto -c -k --norsrc --noextattr --noacl "${STAGE_DIR}" "${DIST_DIR}/${ARCHIVE_NAME}"
cp "${INSTALL_GUIDE}" "${DIST_DIR}/INSTALL.txt"

if [[ -f "${REPO_ROOT}/LICENSE" ]]; then
    cp "${REPO_ROOT}/LICENSE" "${DIST_DIR}/LICENSE.txt"
elif [[ -f "${REPO_ROOT}/LICENSE.txt" ]]; then
    cp "${REPO_ROOT}/LICENSE.txt" "${DIST_DIR}/LICENSE.txt"
fi

echo "==> Verifying staged archive contents"
ditto -x -k "${DIST_DIR}/${ARCHIVE_NAME}" "${VERIFY_DIR}"
[[ -d "${VERIFY_DIR}/${APP_NAME}.app" ]] || { echo "error: ${APP_NAME}.app missing at archive root" >&2; exit 1; }
[[ -f "${VERIFY_DIR}/INSTALL.txt" ]] || { echo "error: INSTALL.txt missing at archive root" >&2; exit 1; }
codesign --verify --deep --strict "${VERIFY_DIR}/${APP_NAME}.app"

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
