#!/usr/bin/env bash
# Henge installer for macOS 13+
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/413d/henge/main/scripts/install.sh | bash
# Optional environment overrides:
#   HENGE_VERSION=v0.1.1          Install a specific release tag
#   HENGE_INSTALL_DIR=~/Apps      Install into a custom directory

set -euo pipefail

main() {
    export PATH="/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

    local repo="413d/henge"
    local expected_bundle_id="io.github.413d.Henge"
    local app_name="Henge.app"

    if [[ "$(uname -s)" != "Darwin" ]]; then
        echo "ERROR: Henge only supports macOS 13 (Ventura) or newer." >&2
        exit 1
    fi

    local macos_version macos_major
    macos_version="$(sw_vers -productVersion)"
    macos_major="${macos_version%%.*}"
    if [[ ! "${macos_major}" =~ ^[0-9]+$ ]] || (( macos_major < 13 )); then
        echo "ERROR: Henge requires macOS 13.0 or newer (detected ${macos_version})." >&2
        exit 1
    fi

    local tag="${HENGE_VERSION:-}"
    local default_api_url="https://api.github.com/repos/${repo}/releases/latest"
    local api_url="${HENGE_API_URL:-${default_api_url}}"

    if [[ -z "${tag}" ]]; then
        local api_json=""
        if api_json="$(curl -fsSL "${api_url}" 2>/dev/null)"; then
            tag="$(printf '%s' "${api_json}" | plutil -extract tag_name raw -o - - 2>/dev/null || true)"
        fi

        if [[ -z "${tag}" && "${api_url}" == "${default_api_url}" ]]; then
            local effective_url=""
            effective_url="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null || true)"
            if [[ "${effective_url}" =~ /releases/tag/([^/?#]+)$ ]]; then
                tag="${BASH_REMATCH[1]}"
            fi
        fi
    fi

    if [[ -z "${tag}" ]]; then
        echo "ERROR: Could not determine latest Henge release version." >&2
        exit 1
    fi

    if [[ "${tag}" != v* ]]; then
        tag="v${tag}"
    fi

    if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
        echo "ERROR: Invalid release tag '${tag}'." >&2
        exit 1
    fi

    local release_base_url="${HENGE_RELEASE_BASE_URL:-https://github.com/${repo}/releases/download}"
    local archive_name="Henge-${tag}-universal.zip"
    local archive_url="${release_base_url}/${tag}/${archive_name}"
    local checksums_url="${release_base_url}/${tag}/SHA256SUMS.txt"

    local work_dir
    work_dir="$(mktemp -d "${TMPDIR:-/tmp}/henge-install.XXXXXX")"
    trap 'rm -rf "${work_dir:-}"' EXIT

    echo "==> Downloading ${archive_name} (${tag})..."
    curl -fsSL "${archive_url}" -o "${work_dir}/${archive_name}"
    curl -fsSL "${checksums_url}" -o "${work_dir}/SHA256SUMS.txt"

    echo "==> Verifying SHA-256 checksum..."
    local expected_sha actual_sha
    expected_sha="$(
        awk -v target="${archive_name}" '
            $2 == target || $2 == ("*" target) {
                print tolower($1)
                exit
            }
        ' "${work_dir}/SHA256SUMS.txt"
    )"

    if [[ ! "${expected_sha}" =~ ^[0-9a-f]{64}$ ]]; then
        echo "ERROR: Could not find valid SHA-256 entry for ${archive_name} in SHA256SUMS.txt." >&2
        exit 1
    fi

    actual_sha="$(shasum -a 256 "${work_dir}/${archive_name}" | awk '{print tolower($1)}')"
    if [[ "${actual_sha}" != "${expected_sha}" ]]; then
        echo "ERROR: SHA-256 checksum mismatch for ${archive_name}." >&2
        echo "  Expected: ${expected_sha}" >&2
        echo "  Actual:   ${actual_sha}" >&2
        exit 1
    fi

    echo "==> Unpacking and verifying code signature..."
    local unpack_dir="${work_dir}/unpacked"
    mkdir -p "${unpack_dir}"
    ditto -x -k "${work_dir}/${archive_name}" "${unpack_dir}"

    local unpacked_app="${unpack_dir}/${app_name}"
    if [[ ! -d "${unpacked_app}" ]]; then
        echo "ERROR: Archive did not contain ${app_name} at root." >&2
        exit 1
    fi

    xattr -dr com.apple.quarantine "${unpacked_app}" 2>/dev/null || true

    if ! codesign --verify --deep --strict "${unpacked_app}" >/dev/null 2>&1; then
        echo "ERROR: Code signature verification failed for ${app_name}." >&2
        exit 1
    fi

    local plist_path="${unpacked_app}/Contents/Info.plist"
    local actual_bundle_id=""
    actual_bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "${plist_path}" 2>/dev/null || true)"
    if [[ "${actual_bundle_id}" != "${expected_bundle_id}" ]]; then
        echo "ERROR: Unexpected CFBundleIdentifier '${actual_bundle_id}' (expected '${expected_bundle_id}')." >&2
        exit 1
    fi

    local install_dir=""
    if [[ -n "${HENGE_INSTALL_DIR:-}" ]]; then
        install_dir="${HENGE_INSTALL_DIR}"
        mkdir -p "${install_dir}"
        if [[ ! -w "${install_dir}" ]]; then
            echo "ERROR: Target directory '${install_dir}' is not writable." >&2
            exit 1
        fi
    else
        local system_apps_dir="${HENGE_SYSTEM_APPS_DIR:-/Applications}"
        if [[ -d "${system_apps_dir}" && -w "${system_apps_dir}" ]] && \
           [[ ! -e "${system_apps_dir}/${app_name}" || -w "${system_apps_dir}/${app_name}" ]]; then
            install_dir="${system_apps_dir}"
        else
            install_dir="${HOME}/Applications"
            mkdir -p "${install_dir}"
            echo "==> '${system_apps_dir}' is not writable without sudo; installing into '${install_dir}'."
        fi
    fi

    if [[ "${HENGE_SKIP_STOP_RUNNING:-false}" != "true" ]]; then
        if pgrep -x "Henge" >/dev/null 2>&1; then
            echo "==> Stopping running Henge instance before upgrade..."
            osascript -e "tell application id \"${expected_bundle_id}\" to quit" >/dev/null 2>&1 || true
            sleep 0.5
            pkill -x "Henge" >/dev/null 2>&1 || true
        fi
    fi

    local target_app="${install_dir}/${app_name}"
    local staging_app="${install_dir}/.${app_name}.staging.$$"
    rm -rf "${staging_app}"
    ditto "${unpacked_app}" "${staging_app}"
    xattr -dr com.apple.quarantine "${staging_app}" 2>/dev/null || true

    rm -rf "${target_app}"
    mv "${staging_app}" "${target_app}"

    echo "==> Installed Henge ${tag} to ${target_app}"
    echo ""
    echo "Next steps:"
    echo "  1. Open Henge: open \"${target_app}\""
    echo "  2. Grant Accessibility permission in:"
    echo "     System Settings -> Privacy & Security -> Accessibility"
}

main "$@"
