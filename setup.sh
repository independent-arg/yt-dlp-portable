#!/bin/bash

# ==============================================================================
# Script Name: yt-dlp-portable (setup.sh)
# Author:      independent-arg
# License:     MIT
#
# Downloads and SHA256-verifies yt-dlp, FFmpeg and Deno into ./bin next to
# this script. Run it again any time to check for updates or reinstall.
# ==============================================================================

set -euo pipefail
shopt -s inherit_errexit

# Follow symlinks before looking for lib.sh, otherwise a symlinked setup.sh
# looks for lib.sh next to the link instead of next to itself.
# resolve_script_path() lives in lib.sh, so it can't be used for this.
_self=$(readlink -f -- "${BASH_SOURCE[0]}" 2>/dev/null) || _self="${BASH_SOURCE[0]}"
LIB_DIR="$(cd "$(dirname "$_self")" && pwd -P)"
unset _self
# shellcheck source=lib.sh
source "${LIB_DIR}/lib.sh"

# ==============================================================================
# BINARY URLS
# ==============================================================================

# Linux (glibc 2.17+) standalone x86_64 binary (nightly is intentional: it
# carries the JS-challenge/format fixes this project depends on)
YTDLP_URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_linux"
YTDLP_SUM_URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/SHA2-256SUMS"

FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
FFMPEG_SUM_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/checksums.sha256"

DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip"
DENO_SUM_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip.sha256sum"

# ==============================================================================
# SYSTEM CHECKS
# ==============================================================================

check_system() {
    local missing_deps=()
    local cmd
    for cmd in curl sha256sum tar xz find grep awk unzip; do
        command -v "$cmd" &> /dev/null || missing_deps+=("$cmd")
    done

    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        _error "Missing required tools: ${missing_deps[*]}"
        _error "Install them via your package manager and try again."
        exit 1
    fi

    if [[ "$(uname -s)" != "Linux" ]]; then
        _error "This script currently supports Linux only."
        exit 1
    fi

    local arch
    arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        _error "Unsupported architecture: $arch"
        _error "This portable version only provides binaries for x86_64 Linux."
        exit 1
    fi
}

# ==============================================================================
# DOWNLOAD AND VERIFICATION HELPERS
# ==============================================================================

download_file() {
    local url="$1" dest="$2"
    local retries=3 attempt=1

    _download "$(basename "$url")"

    while [ "$attempt" -le "$retries" ]; do
        if curl -fL -# --connect-timeout 10 --max-time 300 "$url" -o "$dest"; then
            if [[ -s "$dest" ]]; then
                return 0
            fi
            _warn "Downloaded file is empty, retrying... (attempt $attempt/$retries)"
            rm -f "$dest"
        else
            _warn "Download failed, retrying... (attempt $attempt/$retries)"
        fi

        attempt=$((attempt + 1))
        [ "$attempt" -le "$retries" ] && sleep 2
    done

    _error "Failed to download $(basename "$url") after $retries attempts"
    _error "Please check your internet connection and try again."
    exit 1
}

verify_hash() {
    local file="$1" expected="$2"

    if [[ -z "$expected" ]]; then
        _error "Expected hash is empty for $(basename "$file")"
        exit 1
    fi
    if [[ ! -f "$file" ]]; then
        _error "File not found for hash verification: $file"
        exit 1
    fi

    _verify "Checking SHA256 for $(basename "$file")..."

    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [[ -z "$actual" ]]; then
        _error "Failed to calculate hash for $(basename "$file")"
        exit 1
    fi

    if [[ "${expected,,}" != "${actual,,}" ]]; then
        _error "Hash mismatch for $(basename "$file")!"
        printf "Expected: %s\n" "$expected"
        printf "Actual:   %s\n" "$actual"
        exit 1
    fi

    _ok "Hash verification passed"
}

# ==============================================================================
# VERSION / STATUS DETECTION
#
# Each detector returns one of: not_installed | unknown | <version string>.
# "unknown" means the file exists but wouldn't run (wrong arch, truncated
# download, corrupted binary, etc.), and that's surfaced as "broken" in the menu
# so it isn't confused with a healthy install.
# ==============================================================================

get_ytdlp_version() {
    if [[ -x "${BINDIR}/yt-dlp" ]]; then
        "${BINDIR}/yt-dlp" --version 2>/dev/null || echo "unknown"
    else
        echo "not_installed"
    fi
}

get_ffmpeg_version() {
    if [[ -x "${BINDIR}/ffmpeg" ]]; then
        ( set -o pipefail
          "${BINDIR}/ffmpeg" -version 2>/dev/null | head -n 1 | sed -E 's/^ffmpeg version ([^ ]*).*/\1/'
        ) || echo "unknown"
    else
        echo "not_installed"
    fi
}

get_deno_version() {
    if [[ -x "${BINDIR}/deno" ]]; then
        ( set -o pipefail
          "${BINDIR}/deno" --version 2>/dev/null | head -n 1 | awk '{print $2}'
        ) || echo "unknown"
    else
        echo "not_installed"
    fi
}

# Maps a raw get_*_version() value to: missing | broken | ok
component_state() {
    case "$1" in
        not_installed) echo "missing" ;;
        unknown)        echo "broken" ;;
        *)              echo "ok" ;;
    esac
}

# ==============================================================================
# INSTALL STATE
#
# yt-dlp publishes the checksum of the binary itself, so its update check can
# just hash the installed file. FFmpeg and Deno publish the checksum of the
# archive they ship inside, and that archive is gone once extracted, so what
# was installed gets recorded here and compared against the published checksum
# later. The file lives in bin/.
# ==============================================================================

STATE_FILE=""

read_state() {
    local key="$1" line
    [[ -f "$STATE_FILE" ]] || return 0
    line=$(grep "^${key}=" "$STATE_FILE" | head -n 1) || :
    printf '%s' "${line#"${key}="}"
}

write_state() {
    local key="$1" value="$2"
    local tmp="${STATE_FILE}.tmp"

    if [[ -f "$STATE_FILE" ]]; then
        grep -v "^${key}=" "$STATE_FILE" > "$tmp" 2>/dev/null || :
    else
        : > "$tmp"
    fi
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
    mv -f "$tmp" "$STATE_FILE"
}

# Shared by the FFmpeg and Deno checks: compares the checksum recorded at
# install time against the one currently published upstream.
check_archive_update() {
    local binary="$1" state_key="$2" sums_url="$3" asset_pattern="$4"

    if [[ ! -f "${BINDIR}/${binary}" ]]; then
        echo "missing"
        return
    fi

    local recorded
    recorded=$(read_state "$state_key")
    if [[ -z "$recorded" ]]; then
        # Installed before this was tracked, or the state file was removed.
        echo "unknown"
        return
    fi

    local sums_file="${TEMP_DIR}/${state_key}_check"
    if ! curl -fsSL "$sums_url" -o "$sums_file" 2>/dev/null; then
        echo "error"
        return
    fi

    local latest
    latest=$(grep "$asset_pattern" "$sums_file" | head -n 1 | awk '{print $1}')
    if [[ -z "$latest" ]]; then
        echo "error"
        return
    fi

    if [[ "${latest,,}" == "${recorded,,}" ]]; then
        echo "current"
    else
        echo "outdated"
    fi
}

check_ffmpeg_update() {
    check_archive_update "ffmpeg" "ffmpeg_archive_sha256" "$FFMPEG_SUM_URL" "ffmpeg-master-latest-linux64-gpl.tar.xz"
}

check_deno_update() {
    check_archive_update "deno" "deno_zip_sha256" "$DENO_SUM_URL" "deno-x86_64-unknown-linux-gnu.zip"
}

# Check if yt-dlp needs an update by comparing local hash with the remote one
check_ytdlp_update() {
    if [[ ! -f "${BINDIR}/yt-dlp" ]]; then
        echo "missing"
        return
    fi

    local sums_file="${TEMP_DIR}/yt_check_sums"
    if ! curl -fsSL "$YTDLP_SUM_URL" -o "$sums_file" 2>/dev/null; then
        echo "error"
        return
    fi

    local latest_hash
    latest_hash=$(grep "yt-dlp_linux$" "$sums_file" | head -n 1 | awk '{print $1}')
    if [[ -z "$latest_hash" ]]; then
        echo "error"
        return
    fi

    local current_hash
    current_hash=$(sha256sum "${BINDIR}/yt-dlp" | awk '{print $1}')

    if [[ "${latest_hash,,}" == "${current_hash,,}" ]]; then
        echo "current"
    else
        echo "outdated"
    fi
}

# ==============================================================================
# INSTALLATION FUNCTIONS
# ==============================================================================

install_ytdlp() {
    printf "\n"
    _install "yt-dlp..."

    local sums_file="${TEMP_DIR}/yt_sums"
    local binary_tmp="${TEMP_DIR}/yt-dlp_linux"

    download_file "$YTDLP_SUM_URL" "$sums_file"

    local latest_hash
    latest_hash=$(grep "yt-dlp_linux$" "$sums_file" | head -n 1 | awk '{print $1}')
    if [[ -z "$latest_hash" ]]; then
        _error "Could not extract yt-dlp hash from checksums file"
        exit 1
    fi

    download_file "$YTDLP_URL" "$binary_tmp"
    verify_hash "$binary_tmp" "$latest_hash"

    if ! mv -f "$binary_tmp" "${BINDIR}/yt-dlp" 2>/dev/null; then
        _error "Failed to move yt-dlp to ${BINDIR}"
        exit 1
    fi

    chmod +x "${BINDIR}/yt-dlp"
    rm -f "${sums_file:?}"
    _ok "yt-dlp installed successfully"
}

install_ffmpeg() {
    printf "\n"
    _install "FFmpeg..."

    local sums_file="${TEMP_DIR}/ffmpeg_sums"
    local archive_tmp="${TEMP_DIR}/ffmpeg-master-latest-linux64-gpl.tar.xz"
    local extract_dir="${TEMP_DIR}/ffmpeg_extract"

    download_file "$FFMPEG_SUM_URL" "$sums_file"
    local expected_ff
    expected_ff=$(grep "ffmpeg-master-latest-linux64-gpl.tar.xz" "$sums_file" | head -n 1 | awk '{print $1}')
    if [[ -z "$expected_ff" ]]; then
        _error "Could not find FFmpeg hash in remote file"
        exit 1
    fi

    download_file "$FFMPEG_URL" "$archive_tmp"
    verify_hash "$archive_tmp" "$expected_ff"

    _info "Extracting..."
    rm -rf "$extract_dir" && mkdir -p "$extract_dir"
    if ! tar -xJf "$archive_tmp" -C "$extract_dir"; then
        _error "Failed to extract FFmpeg archive"
        exit 1
    fi

    local ffmpeg_found ffprobe_found
    ffmpeg_found=$(find "$extract_dir" -name "ffmpeg" -type f | head -n 1)
    ffprobe_found=$(find "$extract_dir" -name "ffprobe" -type f | head -n 1)

    if [[ -z "$ffmpeg_found" ]] || [[ -z "$ffprobe_found" ]]; then
        _error "Could not find binaries in extracted archive"
        exit 1
    fi

    mv -f "$ffmpeg_found" "${BINDIR}/ffmpeg"
    mv -f "$ffprobe_found" "${BINDIR}/ffprobe"
    chmod +x "${BINDIR}/ffmpeg" "${BINDIR}/ffprobe"

    write_state "ffmpeg_archive_sha256" "$expected_ff"

    rm -rf "${extract_dir:?}" "${archive_tmp:?}" "${sums_file:?}"
    _ok "FFmpeg installed successfully"
}

install_deno() {
    printf "\n"
    _install "Deno..."

    local sums_file="${TEMP_DIR}/deno_sum"
    local zip_tmp="${TEMP_DIR}/deno.zip"

    download_file "$DENO_SUM_URL" "$sums_file"
    download_file "$DENO_URL" "$zip_tmp"

    local expected_deno
    expected_deno=$(awk '{print $1}' "$sums_file")
    if [[ -z "$expected_deno" ]]; then
        _error "Could not extract Deno hash from checksums file"
        exit 1
    fi

    verify_hash "$zip_tmp" "$expected_deno"

    _info "Extracting..."
    if ! unzip -qo "$zip_tmp" -d "${BINDIR}"; then
        _error "Failed to extract Deno archive"
        exit 1
    fi

    if [[ ! -f "${BINDIR}/deno" ]]; then
        _error "Could not find the deno binary after extraction (unexpected archive layout)"
        exit 1
    fi

    chmod +x "${BINDIR}/deno"
    write_state "deno_zip_sha256" "$expected_deno"

    rm -f "${zip_tmp:?}" "${sums_file:?}"
    _ok "Deno installed successfully"
}

# ==============================================================================
# STATUS DISPLAY AND MENU
# ==============================================================================

# Persist across loop iterations within one run of the menu.
YTDLP_UPDATE_STATUS="unchecked"
FFMPEG_UPDATE_STATUS="unchecked"
DENO_UPDATE_STATUS="unchecked"

print_component_status() {
    local name="$1" version="$2" status="$3"

    case "$status" in
        current)   printf "%b✓%b %s: Version %s (up to date)\n" "${GREEN}" "${NC}" "$name" "$version" ;;
        outdated)  printf "%b⚠%b %s: Version %s (update available)\n" "${YELLOW}" "${NC}" "$name" "$version" ;;
        missing)   printf "%b✗%b %s: Not installed\n" "${RED}" "${NC}" "$name" ;;
        broken)    printf "%b✗%b %s: Installed but not responding (try Force reinstall)\n" "${RED}" "${NC}" "$name" ;;
        unchecked) printf "%b✓%b %s: Version %s (installed)\n" "${GREEN}" "${NC}" "$name" "$version" ;;
        unknown)   printf "%b⚠%b %s: Version %s (installed before update tracking, reinstall to enable it)\n" "${YELLOW}" "${NC}" "$name" "$version" ;;
        error)     printf "%b⚠%b %s: Version %s (update check failed)\n" "${YELLOW}" "${NC}" "$name" "$version" ;;
    esac
}

show_status_and_menu() {
    while true; do
        clear_screen
        show_banner

        local ytdlp_version ffmpeg_version deno_version
        ytdlp_version=$(get_ytdlp_version)
        ffmpeg_version=$(get_ffmpeg_version)
        deno_version=$(get_deno_version)

        local ytdlp_state ffmpeg_state deno_state
        ytdlp_state=$(component_state "$ytdlp_version")
        ffmpeg_state=$(component_state "$ffmpeg_version")
        deno_state=$(component_state "$deno_version")

        # A component that is present and runs gets refined further into
        # current/outdated/unchecked by whatever the last update check said.
        local ytdlp_display="$ytdlp_state" ffmpeg_display="$ffmpeg_state" deno_display="$deno_state"
        [[ "$ytdlp_state" == "ok" ]] && ytdlp_display="$YTDLP_UPDATE_STATUS"
        [[ "$ffmpeg_state" == "ok" ]] && ffmpeg_display="$FFMPEG_UPDATE_STATUS"
        [[ "$deno_state" == "ok" ]] && deno_display="$DENO_UPDATE_STATUS"

        printf "\nComponent Status:\n----------------\n\n"
        print_component_status "yt-dlp" "$ytdlp_version" "$ytdlp_display"
        print_component_status "FFmpeg" "$ffmpeg_version" "$ffmpeg_display"
        print_component_status "Deno" "$deno_version" "$deno_display"

        printf "\nAvailable Actions:\n-----------------\n\n"

        local option_num=1
        local install_missing_option=0 check_updates_option=0 update_option=0 reinstall_option=0 exit_option=0
        local has_missing=false has_installed=false has_updates=false has_unchecked=false

        # A failed check ("error", usually no network) counts as unchecked so
        # the user can simply retry, instead of being left with only the
        # 470 MB "Force reinstall ALL" option until setup is restarted.
        local display
        for display in "$ytdlp_display" "$ffmpeg_display" "$deno_display"; do
            case "$display" in
                missing|broken)  has_missing=true ;;
                outdated)        has_updates=true ;;
                unchecked|error) has_unchecked=true ;;
            esac
        done

        if [[ "$ytdlp_state" != "missing" ]] || [[ "$ffmpeg_state" != "missing" ]] || [[ "$deno_state" != "missing" ]]; then
            has_installed=true
        fi

        if [[ "$has_missing" == true ]]; then
            printf "%d) Install missing components\n" "$option_num"
            install_missing_option=$option_num
            option_num=$((option_num + 1))
        fi

        if [[ "$has_unchecked" == true ]]; then
            printf "%d) Check for updates\n" "$option_num"
            check_updates_option=$option_num
            option_num=$((option_num + 1))
        fi

        if [[ "$has_updates" == true ]]; then
            printf "%d) Update outdated components\n" "$option_num"
            update_option=$option_num
            option_num=$((option_num + 1))
        fi

        if [[ "$has_installed" == true ]]; then
            printf "%d) Force reinstall ALL components\n" "$option_num"
            reinstall_option=$option_num
            option_num=$((option_num + 1))
        fi

        printf "%d) Exit setup\n" "$option_num"
        exit_option=$option_num

        printf "\n"
        local choice
        read -rp "Select option [1-$exit_option]: " choice
        printf "\n"

        if ! [[ "$choice" =~ ^[0-9]{1,4}$ ]] || (( 10#$choice < 1 || 10#$choice > exit_option )); then
            _error "Invalid option: please enter a number between 1 and $exit_option"
            sleep 2
            continue
        fi
        # Normalise "08" to "8": bash would otherwise read a leading zero as
        # octal, and the comparisons below are plain string matches.
        choice=$((10#$choice))

        if [[ "$install_missing_option" != "0" && "$choice" == "$install_missing_option" ]]; then
            if [[ "$ytdlp_display" == "missing" || "$ytdlp_display" == "broken" ]]; then
                install_ytdlp
                YTDLP_UPDATE_STATUS="current"
            fi
            if [[ "$ffmpeg_display" == "missing" || "$ffmpeg_display" == "broken" ]]; then
                install_ffmpeg
                FFMPEG_UPDATE_STATUS="current"
            fi
            if [[ "$deno_display" == "missing" || "$deno_display" == "broken" ]]; then
                install_deno
                DENO_UPDATE_STATUS="current"
            fi

            printf "\n"
            _success "Installation completed"
            _info "Binaries located in: ${BINDIR}"
            press_enter

        elif [[ "$check_updates_option" != "0" && "$choice" == "$check_updates_option" ]]; then
            _info "Checking for updates... (requires internet)"
            [[ "$ytdlp_display" == "unchecked" || "$ytdlp_display" == "error" ]] && YTDLP_UPDATE_STATUS=$(check_ytdlp_update)
            [[ "$ffmpeg_display" == "unchecked" || "$ffmpeg_display" == "error" ]] && FFMPEG_UPDATE_STATUS=$(check_ffmpeg_update)
            [[ "$deno_display" == "unchecked" || "$deno_display" == "error" ]] && DENO_UPDATE_STATUS=$(check_deno_update)

        elif [[ "$update_option" != "0" && "$choice" == "$update_option" ]]; then
            # Only touch what is actually out of date.
            if [[ "$ytdlp_display" == "outdated" ]]; then
                install_ytdlp
                YTDLP_UPDATE_STATUS="current"
            fi
            if [[ "$ffmpeg_display" == "outdated" ]]; then
                install_ffmpeg
                FFMPEG_UPDATE_STATUS="current"
            fi
            if [[ "$deno_display" == "outdated" ]]; then
                install_deno
                DENO_UPDATE_STATUS="current"
            fi
            printf "\n"
            _success "Update completed"
            press_enter

        elif [[ "$reinstall_option" != "0" && "$choice" == "$reinstall_option" ]]; then
            _warn "This will re-download and reinstall ALL components"
            local reply
            read -rp "Continue? (y/N): " -n 1 reply
            printf "\n"
            if [[ "$reply" =~ ^[Yy]$ ]]; then
                install_ytdlp
                install_ffmpeg
                install_deno
                YTDLP_UPDATE_STATUS="current"
                FFMPEG_UPDATE_STATUS="current"
                DENO_UPDATE_STATUS="current"
                printf "\n"
                _success "Full reinstallation completed"
                _info "Binaries located in: ${BINDIR}"
                press_enter
            fi

        elif [[ "$choice" == "$exit_option" ]]; then
            if [[ "$has_missing" == true ]]; then
                _warn "Some components are missing or broken"
                printf "The download script requires all components to function properly\n"
            fi
            exit 0
        fi
    done
}

# ==============================================================================
# MAIN
# ==============================================================================

print_help() {
    printf "yt-dlp-portable Setup Script %s (last updated %s)\n" "$VERSION" "$LAST_UPDATED"
    printf "\n"
    printf "Usage: bash setup.sh [OPTIONS]\n"
    printf "\n"
    printf "This script manages installation and updates of required components:\n"
    printf "  • yt-dlp: Video downloader\n"
    printf "  • FFmpeg: Video/audio processing\n"
    printf "  • Deno: JavaScript runtime for YouTube challenges\n"
    printf "\n"
    printf "The script will detect what's installed and offer appropriate actions.\n"
    printf "\n"
    printf "Options:\n"
    printf "  --help, -h     Show this help message\n"
}

main() {
    # Argument parsing runs before anything else so --help never has to wait
    # on the root check or on creating a temp directory.
    case "${1:-}" in
        --help|-h) print_help; exit 0 ;;
        "") ;;
        *)
            _error "Unknown option: $1"
            _error "Run with --help for usage."
            exit 1
            ;;
    esac

    require_non_root
    check_system

    TEMP_DIR=$(mktemp -d)
    if [[ ! -d "$TEMP_DIR" ]]; then
        _error "Failed to create temporary directory"
        exit 1
    fi
    # Cleanup lives on EXIT only. INT and TERM must actually exit: a handler
    # that just cleans up lets the interrupted script finish with status 0,
    # so Ctrl+C in the middle of an install looked like a success.
    trap 'rm -rf "${TEMP_DIR:?}" 2>/dev/null || true' EXIT
    trap 'printf "\n"; _warn "Interrupted. Components not reported as installed were left as they were."; exit 130' INT
    trap 'exit 143' TERM

    SCRIPT_PATH=$(resolve_script_path)
    BASEDIR=$(dirname "$SCRIPT_PATH")
    BINDIR="${BASEDIR}/bin"
    STATE_FILE="${BINDIR}/.install_state"

    if [[ ! -d "${BINDIR}" ]]; then
        if ! mkdir -p "${BINDIR}" 2>/dev/null; then
            _error "Cannot create directory: ${BINDIR}"
            exit 1
        fi
    fi
    if [[ ! -w "${BINDIR}" ]]; then
        _error "No write permission for: ${BINDIR}"
        exit 1
    fi

    show_status_and_menu
}

main "$@"
