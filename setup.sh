#!/bin/bash

# yt-dlp-portable

set -euo pipefail

# Paths
BASEDIR=$(dirname "$(readlink -f "$0")")
BINDIR="${BASEDIR}/bin"
TEMP_DIR=$(mktemp -d)

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
    for cmd in curl sha256sum tar xz find grep awk; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[ERROR] Missing: $cmd${NC}"
            exit 1
        fi
    done

    # 2. Check Architecture (Crucial for static binaries)
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        echo -e "${YELLOW}[WARN] Your system is $arch. These binaries are for x86_64 and may not work.${NC}"
        sleep 2
    fi
}

download_file() {
    local url="$1"
    local dest="$2"
    echo -e "${GREEN}[DOWNLOAD] $(basename "$url")${NC}"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$url" -o "$dest"
}

verify_hash() {
    local file="$1"
    local expected="$2"
    local actual=$(sha256sum "$file" | awk '{print $1}')
    echo "[VERIFY] Checking SHA256..."
    if [[ "${expected,,}" != "${actual,,}" ]]; then
        echo -e "${RED}[ERROR] Hash Mismatch for $(basename "$file")!${NC}"
        echo "Expected: $expected"
        echo "Actual:   $actual"
        exit 1
    fi
}

# --- Main Execution ---

check_system
mkdir -p "${BINDIR}"

# ---------------------------------------------------------
# 1. yt-dlp (AUTO-UPDATE Logic)
# ---------------------------------------------------------
echo -e "${GREEN}[CHECK] yt-dlp...${NC}"

download_file "$YTDLP_SUM_URL" "${TEMP_DIR}/yt_sums"
LATEST_HASH=$(grep "yt-dlp_linux" "${TEMP_DIR}/yt_sums" | head -n 1 | awk '{print $1}')

CURRENT_HASH=""

if [[ -f "${BINDIR}/yt-dlp" ]]; then
    CURRENT_HASH=$(sha256sum "${BINDIR}/yt-dlp" | awk '{print $1}')
fi

if [[ "$LATEST_HASH" == "$CURRENT_HASH" ]]; then
    echo -e "${YELLOW}  -> yt-dlp is up to date.${NC}"
else
    echo -e "${GREEN}  -> Downloading update...${NC}"
    download_file "$YTDLP_URL" "${TEMP_DIR}/yt-dlp"
    verify_hash "${TEMP_DIR}/yt-dlp" "$LATEST_HASH"
    mv -f "${TEMP_DIR}/yt-dlp" "${BINDIR}/yt-dlp"
    chmod +x "${BINDIR}/yt-dlp"
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
    tar -xJf "${TEMP_DIR}/ffmpeg-master-latest-linux64-gpl.tar.xz" -C "${TEMP_DIR}"

    # We use find because the internal folder may change its name.
    find "${TEMP_DIR}" -name "ffmpeg" -type f -exec mv -f {} "${BINDIR}/" \;
    find "${TEMP_DIR}" -name "ffprobe" -type f -exec mv -f {} "${BINDIR}/" \;

    chmod +x "${BINDIR}/ffmpeg" "${BINDIR}/ffprobe"
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

    verify_hash "${TEMP_DIR}/deno.zip" "$EXPECTED_DENO"

    unzip -qo "${TEMP_DIR}/deno.zip" -d "${BINDIR}"
    chmod +x "${BINDIR}/deno"
fi

echo -e "${GREEN}[SUCCESS] Setup complete. Binaries ready in ${BINDIR}${NC}"
echo "yt-dlp version: $("${BINDIR}/yt-dlp" --version)"
