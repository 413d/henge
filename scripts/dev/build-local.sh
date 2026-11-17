#!/usr/bin/env bash
# Legacy wrapper for local Henge.app build.
# Forwards to scripts/build.sh with backward-compatible defaults.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

FORWARD_ARGS=()
for arg in "$@"; do
    case "$arg" in
        release) FORWARD_ARGS+=("--release") ;;
        debug) FORWARD_ARGS+=("--debug") ;;
        --install) FORWARD_ARGS+=("--install" "/Applications") ;;
        *) FORWARD_ARGS+=("$arg") ;;
    esac
done

exec "${REPO_ROOT}/scripts/build.sh" native ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}
