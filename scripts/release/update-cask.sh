#!/usr/bin/env bash
# Update version and sha256 in Casks/henge.rb after publishing a GitHub Release.
#
# Usage:
#   scripts/release/update-cask.sh <version> <sha256> [cask_path]
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <version> <sha256> [cask_path]" >&2
    exit 2
fi

RAW_VERSION="$1"
VERSION="${RAW_VERSION#v}"
SHA256="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
CASK_PATH="${3:-${REPO_ROOT}/Casks/henge.rb}"

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version '${RAW_VERSION}' must match X.Y.Z (or vX.Y.Z)" >&2
    exit 2
fi

if [[ ! "${SHA256}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "error: sha256 '${2}' must be a 64-character hexadecimal string" >&2
    exit 2
fi

if [[ ! -f "${CASK_PATH}" ]]; then
    echo "error: cask file not found at ${CASK_PATH}" >&2
    exit 1
fi

TMP_FILE="$(mktemp "${TMPDIR:-/tmp}/henge-cask.XXXXXX")"
cleanup() {
    rm -f "${TMP_FILE}"
}
trap cleanup EXIT

sed -E \
    -e "s/^([[:space:]]*version[[:space:]]+\")[^\"]+(\")/\1${VERSION}\2/" \
    -e "s/^([[:space:]]*sha256[[:space:]]+\")[^\"]+(\")/\1${SHA256}\2/" \
    "${CASK_PATH}" > "${TMP_FILE}"

grep -q "version \"${VERSION}\"" "${TMP_FILE}" \
    || { echo "error: failed to update version in ${CASK_PATH}" >&2; exit 1; }
grep -q "sha256 \"${SHA256}\"" "${TMP_FILE}" \
    || { echo "error: failed to update sha256 in ${CASK_PATH}" >&2; exit 1; }

if command -v ruby >/dev/null 2>&1; then
    ruby -c "${TMP_FILE}" >/dev/null
fi

mv "${TMP_FILE}" "${CASK_PATH}"
echo "Updated ${CASK_PATH} -> version ${VERSION} (sha256: ${SHA256})"
