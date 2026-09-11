#!/bin/bash
# ==============================================================================
# yt-dlp-portable shared library
#
# Sourced by setup.sh and download.sh. Not meant to be executed directly;
# it only defines constants and functions, and relies on the caller having
# already done `set -euo pipefail`.
# ==============================================================================

readonly VERSION="v0.12.0"
# shellcheck disable=SC2034 # consumed by setup.sh/download.sh --help output
readonly LAST_UPDATED="2026-09-11"

# Colors are skipped when stdout isn't a terminal (piped to a file/log, or
# NO_COLOR is set) so redirected output and cron logs don't fill up with
# escape codes.
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    NC='\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

_info()     { printf -- "%b\n" "${CYAN}[INFO]${NC} $*"; }
_success()  { printf -- "%b\n" "${GREEN}[SUCCESS]${NC} $*"; }
_ok()       { printf -- "%b\n" "${GREEN}[OK]${NC} $*"; }
_warn()     { printf -- "%b\n" "${YELLOW}[WARN]${NC} $*"; }
_error()    { printf -- "%b\n" "${RED}[ERROR]${NC} $*" >&2; }
_download() { printf -- "%b\n" "${GREEN}[DOWNLOAD]${NC} $*"; }
_verify()   { printf -- "%b\n" "${YELLOW}[VERIFY]${NC} $*"; }
_install()  { printf -- "%b\n" "${GREEN}[INSTALL]${NC} $*"; }

# Resolves the real, symlink-free absolute path of the top-level script that
# sourced this library (i.e. "$0" of setup.sh / download.sh). Dies loudly if
# it can't, instead of silently falling back to a wrong directory.
resolve_script_path() {
    local path
    if command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
        path=$(readlink -f "$0")
    else
        path="$(cd "$(dirname "$0")" && pwd -P)/$(basename "$0")"
    fi

    # readlink -f can resolve a broken symlink without error, so verify the
    # target actually exists.
    if [[ ! -f "$path" ]]; then
        _error "Could not resolve the script location (broken symlink?): $path"
        exit 1
    fi
    printf '%s' "$path"
}

require_non_root() {
    if [[ "$EUID" -eq 0 ]]; then
        _error "Please do not run this as root."
        _error "It installs binaries into a local directory and does not need root privileges."
        exit 1
    fi
}

show_banner() {
    local banner_line="============================================"
    local width=${#banner_line}
    local text1="yt-dlp-portable independent-arg"
    local text2="$VERSION"

    local text
    for text in "$text1" "$text2"; do
        (( ${#text} > width )) && width=${#text}
    done
    banner_line=$(printf "%*s" "$width" "" | tr ' ' '=')

    _print_centered() {
        local text="$1" color="$2"
        local pad=$(( (width - ${#text}) / 2 ))
        printf "%b%*s%s%*s%b\n" "$color" "$pad" "" "$text" "$((width - ${#text} - pad))" "" "$NC"
    }

    printf "\n%b%s%b\n" "$BLUE" "$banner_line" "$NC"
    _print_centered "$text1" "$CYAN"
    _print_centered "$text2" "$YELLOW"
    printf "%b%s%b\n\n" "$BLUE" "$banner_line" "$NC"
}

press_enter() {
    printf "\n"
    read -rp "Press Enter to continue..."
}

# `clear` needs a usable TERM. Without one (docker exec without -t, some ssh
# and cron setups) it exits non-zero, and under set -e that takes the whole
# script down. Clearing is cosmetic, so it must never be fatal, and it is
# skipped entirely when output is not a terminal so logs stay clean.
clear_screen() {
    if [[ -t 1 ]]; then
        clear 2>/dev/null || printf '\033[H\033[2J'
    fi
}
