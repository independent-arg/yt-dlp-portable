#!/bin/bash

# ==============================================================================
# Script Name: yt-dlp-portable (setup.sh)
# Version:     v0.9.0
# Author:      independent-arg
# License:     MIT
# ==============================================================================

set -euo pipefail
shopt -s inherit_errexit

readonly VERSION="v0.9.0"
readonly LAST_UPDATED="2026-06-23"

# Paths
if command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
    BASEDIR=$(dirname "$(readlink -f "$0")")
else
    # Fallback for systems without readlink -f
    BASEDIR=$(cd "$(dirname "$0")" && pwd -P)
fi
BINDIR="${BASEDIR}/bin"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ==============================================================================
# OUTPUT HELPER FUNCTIONS
# ==============================================================================

_info()     { printf -- "%b\n" "${CYAN}[INFO]${NC} $*"; }
_success()  { printf -- "%b\n" "${GREEN}[SUCCESS]${NC} $*"; }
_ok()       { printf -- "%b\n" "${GREEN}[OK]${NC} $*"; }
_warn()     { printf -- "%b\n" "${YELLOW}[WARN]${NC} $*"; }
_error()    { printf -- "%b\n" "${RED}[ERROR]${NC} $*"; }
_download() { printf -- "%b\n" "${GREEN}[DOWNLOAD]${NC} $*"; }
_verify()   { printf -- "%b\n" "${YELLOW}[VERIFY]${NC} $*"; }
_install()  { printf -- "%b\n" "${GREEN}[INSTALL]${NC} $*"; }


# Security: Prevent execution as root
if [ "$EUID" -eq 0 ]; then
    _error "Please do not run this script as root. This script installs binaries to a local directory and does not require root privileges."
    exit 1
fi

# ==============================================================================
# TEMPORARY DIRECTORY SETUP
# ==============================================================================

TEMP_DIR=$(mktemp -d)
if [[ ! -d "$TEMP_DIR" ]]; then
    _error "Failed to create temporary directory"
    exit 1
fi

# Cleanup temp on exit (success or fail)
trap 'rm -rf "${TEMP_DIR:?}" || true' EXIT INT TERM

# ==============================================================================
# BINARY URLS
# ==============================================================================

# Linux (glibc 2.17+) standalone x86_64 binary (nightly version - recommended from yt-dlp)
YTDLP_URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/yt-dlp_linux"
YTDLP_SUM_URL="https://github.com/yt-dlp/yt-dlp-nightly-builds/releases/latest/download/SHA2-256SUMS"

FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
FFMPEG_SUM_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/checksums.sha256"

DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip"
DENO_SUM_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip.sha256sum"

# --- Helpers ---

check_system() {
    # 1. Check Dependencies
    local missing_deps=()
    for cmd in curl sha256sum tar xz find grep awk unzip; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
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

    # 2. Check Architecture (Crucial for static binaries)
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
    local url="$1"
    local dest="$2"
    local retries=3
    local attempt=1
    
    _download "$(basename "$url")"
    
    while [ $attempt -le $retries ]; do
        if curl -fL -# --connect-timeout 10 --max-time 300 "$url" -o "$dest"; then
            if [[ -s "$dest" ]]; then
                return 0
            else
                _warn "Downloaded file is empty, retrying... (attempt $attempt/$retries)"
                rm -f "$dest"
            fi
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
    local file="$1"
    local expected="$2"
    
    # Validate inputs
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
# VERSION DETECTION FUNCTIONS
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

# ==============================================================================
# UPDATE CHECK FUNCTIONS
# ==============================================================================

# Check if yt-dlp needs update by comparing local hash with remote
check_ytdlp_update() {
    if [[ ! -f "${BINDIR}/yt-dlp" ]]; then
        echo "missing"
        return
    fi
    
    local sums_file
    sums_file="${TEMP_DIR}/yt_check_sums"

    # Download remote checksums
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

    local sums_file
    sums_file="${TEMP_DIR}/yt_sums"
    local binary_tmp
    binary_tmp="${TEMP_DIR}/yt-dlp_linux"

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
    rm -f "${sums_file:?Error: variable is empty}"
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

    rm -rf "${extract_dir:?Error: extract_dir is empty}" "${archive_tmp:?Error: archive_tmp is empty}" "${sums_file:?Error: sums_file is empty}"
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

    chmod +x "${BINDIR}/deno"
    rm -f "${zip_tmp:?Error: zip_tmp is empty}" "${sums_file:?Error: sums_file is empty}"
    _ok "Deno installed successfully"
}

# ==============================================================================
# BANNER DISPLAY
# ==============================================================================

show_banner() {
    local banner_line="============================================"
    local width=${#banner_line}
    local text1="yt-dlp-portable independent-arg"
    local text2="${VERSION}"

    for text in "$text1" "$text2"; do
        if (( ${#text} > width )); then
            width=${#text}
        fi
    done

    banner_line=$(printf "%*s" "${width}" "" | tr ' ' '=')

    _print_centered() {
        local text="$1"
        local color="$2"
        local text_len=${#text}
        local padding=$(( (width - text_len) / 2 ))

        printf "%b%*s%s%*s%b\n" "${color}" "${padding}" "" "${text}" "$((width - text_len - padding))" "" "${NC}"
    }

    printf "\n"
    printf "%b%s%b\n" "${BLUE}" "${banner_line}" "${NC}"
    _print_centered "$text1" "${CYAN}"
    _print_centered "$text2" "${YELLOW}"
    printf "%b%s%b\n" "${BLUE}" "${banner_line}" "${NC}"
    printf "\n"
}

# ==============================================================================
# STATUS DISPLAY AND MENU
# ==============================================================================

# Global state for update check to persist across recursions
YTDLP_UPDATE_STATUS="unchecked"

show_status_and_menu() {
    while true; do
        clear
        show_banner

        # Detect what's installed
        local ytdlp_version ffmpeg_version deno_version ytdlp_status_display

        ytdlp_version=$(get_ytdlp_version)
        ffmpeg_version=$(get_ffmpeg_version)
        deno_version=$(get_deno_version)

        # Determine display status for yt-dlp
        if [[ "$ytdlp_version" == "not_installed" ]]; then
            ytdlp_status_display="missing"
        else
            # Installed, check global state
            ytdlp_status_display="$YTDLP_UPDATE_STATUS"
        fi

        printf "\n"
        printf "%s\n" "Component Status:"
        printf "%s\n" "----------------"
        printf "\n"

        # yt-dlp status
        case "$ytdlp_status_display" in
            "current")
                printf "%b✓%b yt-dlp: Version %s (up to date)\n" "${GREEN}" "${NC}" "$ytdlp_version"
                ;;
            "outdated")
                printf "%b⚠%b yt-dlp: Version %s (update available)\n" "${YELLOW}" "${NC}" "$ytdlp_version"
                ;;
            "missing")
                printf "%b✗%b yt-dlp: Not installed\n" "${RED}" "${NC}"
                ;;
            "unchecked")
                printf "%b✓%b yt-dlp: Version %s (installed)\n" "${GREEN}" "${NC}" "$ytdlp_version"
                ;;
            "error")
                printf "%b⚠%b yt-dlp: Version %s (update check failed)\n" "${YELLOW}" "${NC}" "$ytdlp_version"
                ;;
        esac

        # FFmpeg status (no update checking - just shows installed version)
        if [[ "$ffmpeg_version" == "not_installed" ]]; then
            printf "%b✗%b FFmpeg: Not installed\n" "${RED}" "${NC}"
        else
            printf "%b✓%b FFmpeg: Version %s (installed)\n" "${GREEN}" "${NC}" "$ffmpeg_version"
        fi

        # Deno status (no update checking - just shows installed version)
        if [[ "$deno_version" == "not_installed" ]]; then
            printf "%b✗%b Deno: Not installed\n" "${RED}" "${NC}"
        else
            printf "%b✓%b Deno: Version %s (installed)\n" "${GREEN}" "${NC}" "$deno_version"
        fi

        printf "\n"
        printf "%s\n" "Available Actions:"
        printf "%s\n" "-----------------"
        printf "\n"

        # Build menu based on current state
        local option_num=1
        local install_missing_option=0
        local check_updates_option=0
        local update_option=0
        local reinstall_option=0
        local exit_option=0

        # Global state
        local has_missing=false
        local has_installed=false
        local has_updates=false

        # Check if anything is missing
        if [[ "$ytdlp_status_display" == "missing" ]] || [[ "$ffmpeg_version" == "not_installed" ]] || \
        [[ "$deno_version" == "not_installed" ]]; then
            has_missing=true
        fi

        # Check if anything is already installed
        if [[ "$ytdlp_status_display" != "missing" ]] || [[ "$ffmpeg_version" != "not_installed" ]] || \
        [[ "$deno_version" != "not_installed" ]]; then
            has_installed=true
        fi

        # Check if updates available
        if [[ "$ytdlp_status_display" == "outdated" ]]; then
            has_updates=true
        fi

        # Show appropriate options
        if [[ "$has_missing" == true ]]; then
            printf "%d) Install missing components\n" "$option_num"
            install_missing_option=$option_num
            option_num=$((option_num + 1))
        fi

        # Option to check for updates (only if installed and not already checked)
        if [[ "$ytdlp_status_display" == "unchecked" ]]; then
            printf "%d) Check for updates\n" "$option_num"
            check_updates_option=$option_num
            option_num=$((option_num + 1))
        fi

        if [[ "$has_updates" == true ]]; then
            printf "%d) Update yt-dlp to latest version\n" "$option_num"
            update_option=$option_num
            option_num=$((option_num + 1))
        fi

        # Only show reinstall option if something is already installed

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

        # Validate that input is a number before processing

        if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > exit_option )); then
            _error "Invalid option: please enter a number between 1 and $exit_option"
            sleep 2
            continue
        fi

        # Process choice
        if [[ "$install_missing_option" != "0" && "$choice" == "$install_missing_option" ]]; then
            # Install missing
            [[ "$ytdlp_status_display" == "missing" ]] && install_ytdlp
            [[ "$ffmpeg_version" == "not_installed" ]] && install_ffmpeg
            [[ "$deno_version" == "not_installed" ]] && install_deno

            # After install, we are current
            YTDLP_UPDATE_STATUS="current"

            printf "\n"
            _success "Installation completed"
            _info "Binaries located in: ${BINDIR}"
            printf "\n"
            read -rp "Press Enter to continue..."

        elif [[ "$check_updates_option" != "0" && "$choice" == "$check_updates_option" ]]; then
            # Check for updates
            _info "Checking yt-dlp for updates... (requires internet)"
            YTDLP_UPDATE_STATUS=$(check_ytdlp_update)

        elif [[ "$update_option" != "0" && "$choice" == "$update_option" ]]; then
            # Update yt-dlp
            install_ytdlp
            YTDLP_UPDATE_STATUS="current"
            printf "\n"
            _success "Update completed"
            printf "\n"
            read -rp "Press Enter to continue..."

        elif [[ "$reinstall_option" != "0" && "$choice" == "$reinstall_option" ]]; then
            # Force reinstall (only if components are installed)
            _warn "This will re-download and reinstall ALL components"
            local REPLY
            read -p "Continue? (y/N): " -n 1 -r
            printf "\n"
            if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                install_ytdlp
                install_ffmpeg
                install_deno
                YTDLP_UPDATE_STATUS="current"
                printf "\n"
                _success "Full reinstallation completed"
                _info "Binaries located in: ${BINDIR}"
                printf "\n"
                read -rp "Press Enter to continue..."
            fi

        elif [[ "$choice" == "$exit_option" ]]; then
            # Exit
            if [[ "$has_missing" == true ]]; then
                _warn "Some components are missing"
                printf "The download script requires all components to function properly\n"
            fi
            exit 0
        fi
    done
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

main() {
    # Parse arguments
    if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
        printf "yt-dlp-portable Setup Script %s\n" "${VERSION}"
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
        printf "\n"
        exit 0
    fi
    
    # System checks
    check_system
    
    # Create bin directory if needed
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
    
    # Show interactive menu
    show_status_and_menu
}

main "$@"
