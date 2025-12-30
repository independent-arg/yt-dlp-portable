#!/bin/bash

# ==============================================================================
# Script Name: yt-dlp-portable (setup.sh)
# Version:     v0.5.1
# Author:      independent-arg
# License:     MIT
# ==============================================================================

set -euo pipefail

readonly VERSION="v0.5.1"

# Paths
# Robust path resolution (works on Linux, macOS, BSD)
if command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
    BASEDIR=$(dirname "$(readlink -f "$0")")
else
    # Fallback for systems without readlink -f
    BASEDIR=$(cd "$(dirname "$0")" && pwd -P)
fi
BINDIR="${BASEDIR}/bin"

# Colors (must be defined before any usage)
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Security: Prevent execution as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}[ERROR] Please do not run this script as root.${NC}"
    echo -e "${RED}This script installs binaries to a local directory and does not require root privileges.${NC}"
    exit 1
fi

TEMP_DIR=$(mktemp -d)
if [[ ! -d "$TEMP_DIR" ]]; then
    echo -e "${RED}[ERROR] Failed to create temporary directory${NC}"
    exit 1
fi

# Cleanup temp on exit (success or fail)
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Linux (glibc 2.17+) standalone x86_64 binary
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux"
YTDLP_SUM_URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/SHA2-256SUMS"

FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-linux64-gpl.tar.xz"
FFMPEG_SUM_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/latest/checksums.sha256"

DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip"
DENO_SUM_URL="https://github.com/denoland/deno/releases/latest/download/deno-x86_64-unknown-linux-gnu.zip.sha256sum"

# --- Helpers ---

check_system() {
    # 1. Check Dependencies
    for cmd in curl sha256sum tar xz find grep awk unzip; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[ERROR] Missing: $cmd${NC}"
            echo -e "${RED}Please install the missing dependency and try again.${NC}"
            exit 1
        fi
    done

    # 2. Check Architecture (Crucial for static binaries)
    local arch
    arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        echo -e "${YELLOW}[WARN] Your system is $arch. These binaries are for x86_64 and may not work.${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    local retries=3
    local attempt=1
    
    echo -e "${GREEN}[DOWNLOAD] $(basename "$url")${NC}"
    
    while [ $attempt -le $retries ]; do
        if curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 10 --max-time 300 "$url" -o "$dest" 2>/dev/null; then
            # Verify file was downloaded and is not empty
            if [[ -s "$dest" ]]; then
                return 0
            else
                echo -e "${YELLOW}[WARN] Downloaded file is empty, retrying... (attempt $attempt/$retries)${NC}"
                rm -f "$dest"
            fi
        else
            echo -e "${YELLOW}[WARN] Download failed, retrying... (attempt $attempt/$retries)${NC}"
        fi
        
        attempt=$((attempt + 1))
        sleep 2
    done
    
    echo -e "${RED}[ERROR] Failed to download $(basename "$url") after $retries attempts${NC}"
    echo -e "${RED}Please check your internet connection and try again.${NC}"
    exit 1
}

verify_hash() {
    local file="$1"
    local expected="$2"
    
    # Validate inputs
    if [[ -z "$expected" ]]; then
        echo -e "${RED}[ERROR] Expected hash is empty for $(basename "$file")${NC}"
        exit 1
    fi
    
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}[ERROR] File not found for hash verification: $file${NC}"
        exit 1
    fi
    
    local actual
    actual=$(sha256sum "$file" | awk '{print $1}')
    if [[ -z "$actual" ]]; then
        echo -e "${RED}[ERROR] Failed to calculate hash for $(basename "$file")${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}[VERIFY] Checking SHA256...${NC}"
    if [[ "${expected,,}" != "${actual,,}" ]]; then
        echo -e "${RED}[ERROR] Hash Mismatch for $(basename "$file")!${NC}"
        echo "Expected: $expected"
        echo "Actual:   $actual"
        exit 1
    fi
    echo -e "${GREEN}  -> Hash verification passed${NC}"
}

# --- Main Execution ---

check_system

# Check write permissions for BINDIR
if ! mkdir -p "${BINDIR}" 2>/dev/null; then
    echo -e "${RED}[ERROR] Cannot create directory: ${BINDIR}${NC}"
    echo -e "${RED}Please check permissions or choose a different location.${NC}"
    exit 1
fi

# Verify write permissions
if [[ ! -w "${BINDIR}" ]]; then
    echo -e "${RED}[ERROR] No write permission for: ${BINDIR}${NC}"
    echo -e "${RED}Please fix permissions and try again.${NC}"
    exit 1
fi

# ---------------------------------------------------------
# 1. yt-dlp (AUTO-UPDATE Logic)
# ---------------------------------------------------------
echo -e "${GREEN}[CHECK] yt-dlp...${NC}"

download_file "$YTDLP_SUM_URL" "${TEMP_DIR}/yt_sums"
LATEST_HASH=$(grep "yt-dlp_linux" "${TEMP_DIR}/yt_sums" | head -n 1 | awk '{print $1}')

# Validate that we got a hash
if [[ -z "$LATEST_HASH" ]]; then
    echo -e "${RED}[ERROR] Could not extract yt-dlp hash from checksums file${NC}"
    exit 1
fi

CURRENT_HASH=""

if [[ -f "${BINDIR}/yt-dlp" ]]; then
    CURRENT_HASH=$(sha256sum "${BINDIR}/yt-dlp" | awk '{print $1}')
fi

if [[ -n "$CURRENT_HASH" && "$LATEST_HASH" == "$CURRENT_HASH" ]]; then
    echo -e "${YELLOW}  -> yt-dlp is up to date.${NC}"
else
    echo -e "${GREEN}  -> Downloading update...${NC}"
    download_file "$YTDLP_URL" "${TEMP_DIR}/yt-dlp"
    verify_hash "${TEMP_DIR}/yt-dlp" "$LATEST_HASH"
    if ! mv -f "${TEMP_DIR}/yt-dlp" "${BINDIR}/yt-dlp" 2>/dev/null; then
        echo -e "${RED}[ERROR] Failed to move yt-dlp to ${BINDIR}${NC}"
        echo -e "${RED}Please check write permissions.${NC}"
        exit 1
    fi
    chmod +x "${BINDIR}/yt-dlp"
    echo -e "${GREEN}  -> yt-dlp updated successfully${NC}"
fi

# ---------------------------------------------------------
# 2. FFmpeg (Static Logic)
# ---------------------------------------------------------
if [[ -x "${BINDIR}/ffmpeg" && -x "${BINDIR}/ffprobe" ]]; then
    echo -e "${YELLOW}[CHECK] FFmpeg exists. Skipping.${NC}"
else
    echo -e "${GREEN}[INSTALL] FFmpeg (Latest)...${NC}"

    # 1. Download Checksums file
    download_file "$FFMPEG_SUM_URL" "${TEMP_DIR}/ffmpeg_sums"

    # 2. Find the specific hash for the Linux64 GPL version
    # The file contains lines such as: “hash filename”
    EXPECTED_FF=$(grep "ffmpeg-master-latest-linux64-gpl.tar.xz" "${TEMP_DIR}/ffmpeg_sums" | head -n 1 | awk '{print $1}')

    if [[ -z "$EXPECTED_FF" ]]; then
        echo -e "${RED}[ERROR] Could not find FFmpeg hash in remote file!${NC}"
        exit 1
    fi

    # 3. Download binary
    download_file "$FFMPEG_URL" "${TEMP_DIR}/ffmpeg-master-latest-linux64-gpl.tar.xz"

    # 4. Verify hash
    verify_hash "${TEMP_DIR}/ffmpeg-master-latest-linux64-gpl.tar.xz" "$EXPECTED_FF"

    # 5. Install
    echo "  -> Extracting..."
    if ! tar -xJf "${TEMP_DIR}/ffmpeg-master-latest-linux64-gpl.tar.xz" -C "${TEMP_DIR}"; then
        echo -e "${RED}[ERROR] Failed to extract FFmpeg archive${NC}"
        exit 1
    fi

    # We use find because the internal folder may change its name.
    FFMPEG_FOUND=$(find "${TEMP_DIR}" -name "ffmpeg" -type f | head -n 1)
    FFPROBE_FOUND=$(find "${TEMP_DIR}" -name "ffprobe" -type f | head -n 1)
    
    if [[ -z "$FFMPEG_FOUND" ]]; then
        echo -e "${RED}[ERROR] Could not find ffmpeg binary in extracted archive${NC}"
        exit 1
    fi
    
    if [[ -z "$FFPROBE_FOUND" ]]; then
        echo -e "${RED}[ERROR] Could not find ffprobe binary in extracted archive${NC}"
        exit 1
    fi
    
    if ! mv -f "$FFMPEG_FOUND" "${BINDIR}/ffmpeg" 2>/dev/null; then
        echo -e "${RED}[ERROR] Failed to move ffmpeg to ${BINDIR}${NC}"
        echo -e "${RED}Please check write permissions.${NC}"
        exit 1
    fi
    if ! mv -f "$FFPROBE_FOUND" "${BINDIR}/ffprobe" 2>/dev/null; then
        echo -e "${RED}[ERROR] Failed to move ffprobe to ${BINDIR}${NC}"
        echo -e "${RED}Please check write permissions.${NC}"
        exit 1
    fi
    chmod +x "${BINDIR}/ffmpeg" "${BINDIR}/ffprobe"
    echo -e "${GREEN}  -> FFmpeg installed successfully${NC}"
fi

# ---------------------------------------------------------
# 3. Deno (Static Logic)
# ---------------------------------------------------------
if [[ -x "${BINDIR}/deno" ]]; then
    echo -e "${YELLOW}[CHECK] Deno exists. Skipping.${NC}"
else
    echo -e "${GREEN}[INSTALL] Deno (JS Runtime)...${NC}"

    download_file "$DENO_SUM_URL" "${TEMP_DIR}/deno_sum"
    download_file "$DENO_URL" "${TEMP_DIR}/deno.zip"

    EXPECTED_DENO=$(grep "deno-x86_64-unknown-linux-gnu.zip" "${TEMP_DIR}/deno_sum" | awk '{print $1}')
    
    # Validate that we got a hash
    if [[ -z "$EXPECTED_DENO" ]]; then
        echo -e "${RED}[ERROR] Could not extract Deno hash from checksums file${NC}"
        exit 1
    fi

    verify_hash "${TEMP_DIR}/deno.zip" "$EXPECTED_DENO"

    echo "  -> Extracting..."
    if ! unzip -qo "${TEMP_DIR}/deno.zip" -d "${BINDIR}"; then
        echo -e "${RED}[ERROR] Failed to extract Deno archive${NC}"
        exit 1
    fi
    
    if [[ ! -f "${BINDIR}/deno" ]]; then
        echo -e "${RED}[ERROR] Deno binary not found after extraction${NC}"
        exit 1
    fi
    
    chmod +x "${BINDIR}/deno"
    echo -e "${GREEN}  -> Deno installed successfully${NC}"
fi

echo -e "${GREEN}[SUCCESS] Setup complete. Binaries ready in ${BINDIR}${NC}"

# Verify yt-dlp works (but don't fail if it doesn't - it might be a compatibility issue)
if "${BINDIR}/yt-dlp" --version >/dev/null 2>&1; then
    echo "yt-dlp version: $("${BINDIR}/yt-dlp" --version)"
else
    echo -e "${YELLOW}[WARN] Could not verify yt-dlp version (binary may not be compatible)${NC}"
fi
