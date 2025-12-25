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

# --- Resources (Locked Versions: Linux x64) ---
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/2025.12.08/yt-dlp"
YTDLP_SHA256="aed043cabf6b352dfd5438afff595e31532538d5af7c8f4f95ced1e6f1b35c2a"

FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/autobuild-2025-12-24-14-14/ffmpeg-N-122252-g548b28d5b1-linux64-gpl.tar.xz"
FFMPEG_SHA256="ad2f7f3e0d5b04ccbb0ab5375982055e06189552a8a659fcb7ce4309932f28f4"

NODE_URL="https://nodejs.org/dist/latest-v25.x/node-v25.2.1-linux-x64.tar.xz"
NODE_SHA256="b9f6a97e81c89a9df45526b4f86dafdccaf12b82295f7bf35bdb2b0f5e68744f"

# --- Helpers ---

check_system() {
    # 1. Check Dependencies
    for cmd in curl sha256sum tar xz find; do
        if ! command -v "$cmd" &> /dev/null; then
            echo -e "${RED}[ERROR] Missing system tool: $cmd${NC}"
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

download_verify() {
    local url="$1"
    local dest="$2"
    local sha="$3"

    echo -e "${GREEN}[DOWNLOAD] ${url##*/}${NC}"
    curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 "$url" -o "$dest"

    echo "[VERIFY] Checking SHA256..."
    echo "$sha  $dest" | sha256sum --check --status || {
        echo -e "${RED}[ERROR] Hash mismatch for ${dest}${NC}"
        exit 1
    }
}

# --- Main Execution ---

check_system
mkdir -p "${BINDIR}"

# 1. yt-dlp
download_verify "$YTDLP_URL" "${BINDIR}/yt-dlp" "$YTDLP_SHA256"
chmod +x "${BINDIR}/yt-dlp"

# 2. FFmpeg
rm -f "${BINDIR}/ffmpeg" "${BINDIR}/ffprobe" # Clean old
download_verify "$FFMPEG_URL" "${TEMP_DIR}/ffmpeg.tar.xz" "$FFMPEG_SHA256"

echo "[EXTRACT] FFmpeg..."
tar -xf "${TEMP_DIR}/ffmpeg.tar.xz" -C "${TEMP_DIR}"
find "${TEMP_DIR}" -type f -name "ffmpeg" -exec mv -f {} "${BINDIR}/" \;
find "${TEMP_DIR}" -type f -name "ffprobe" -exec mv -f {} "${BINDIR}/" \;

# Immediate validation
if [[ ! -x "${BINDIR}/ffmpeg" ]]; then
    echo -e "${RED}[ERROR] FFmpeg extraction failed.${NC}"; exit 1
fi
chmod +x "${BINDIR}/ffmpeg" "${BINDIR}/ffprobe"

# 3. Node.js
rm -f "${BINDIR}/node" # Clean old
download_verify "$NODE_URL" "${TEMP_DIR}/node.tar.xz" "$NODE_SHA256"

echo "[EXTRACT] Node.js..."
tar -xf "${TEMP_DIR}/node.tar.xz" -C "${TEMP_DIR}"
find "${TEMP_DIR}" -type f -name "node" -exec mv -f {} "${BINDIR}/" \;

# Immediate validation
if [[ ! -x "${BINDIR}/node" ]]; then
    echo -e "${RED}[ERROR] Node.js extraction failed.${NC}"; exit 1
fi
chmod +x "${BINDIR}/node"

echo -e "${GREEN}[SUCCESS] Setup complete. Binaries ready in ${BINDIR}${NC}"
"${BINDIR}/yt-dlp" --version