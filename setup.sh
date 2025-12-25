#!/bin/bash

# yt-dlp-portable

set -e
set -o pipefail

# Directory configuration
BASEDIR=$(dirname "$(readlink -f "$0")")
BINDIR="${BASEDIR}/bin"
TEMP_DIR=$(mktemp -d)

# Cleanup trap
trap 'rm -rf "${TEMP_DIR}"' EXIT

# Resource Configuration (Locked Versions)
YTDLP_URL="https://github.com/yt-dlp/yt-dlp/releases/download/2025.12.08/yt-dlp"
YTDLP_SHA256="aed043cabf6b352dfd5438afff595e31532538d5af7c8f4f95ced1e6f1b35c2a"

FFMPEG_URL="https://github.com/yt-dlp/FFmpeg-Builds/releases/download/autobuild-2025-12-24-14-14/ffmpeg-N-122252-g548b28d5b1-linux64-gpl.tar.xz"
FFMPEG_SHA256="ad2f7f3e0d5b04ccbb0ab5375982055e06189552a8a659fcb7ce4309932f28f4"

NODE_URL="https://nodejs.org/dist/latest-v25.x/node-v25.2.1-linux-x64.tar.xz"
NODE_SHA256="b9f6a97e81c89a9df45526b4f86dafdccaf12b82295f7bf35bdb2b0f5e68744f"

echo "[INFO] Initializing environment at ${BINDIR}"
mkdir -p "${BINDIR}"

# 1. Provision yt-dlp
echo "[INFO] Downloading yt-dlp..."
curl -fsSL "${YTDLP_URL}" -o "${BINDIR}/yt-dlp"
echo "${YTDLP_SHA256}  ${BINDIR}/yt-dlp" | sha256sum --check --status
chmod +x "${BINDIR}/yt-dlp"

# 2. Provision FFmpeg
echo "[INFO] Downloading FFmpeg static build..."
curl -fsSL "${FFMPEG_URL}" -o "${TEMP_DIR}/ffmpeg.tar.xz"
echo "${FFMPEG_SHA256}  ${TEMP_DIR}/ffmpeg.tar.xz" | sha256sum --check --status
# Extract to temp and find/move to avoid path depth errors
tar -xf "${TEMP_DIR}/ffmpeg.tar.xz" -C "${TEMP_DIR}"
find "${TEMP_DIR}" -type f -name "ffmpeg" -exec mv {} "${BINDIR}/" \;
find "${TEMP_DIR}" -type f -name "ffprobe" -exec mv {} "${BINDIR}/" \;
chmod +x "${BINDIR}/ffmpeg" "${BINDIR}/ffprobe"

# 3. Provision Node.js
echo "[INFO] Downloading Node.js runtime..."
curl -fsSL "${NODE_URL}" -o "${TEMP_DIR}/node.tar.xz"
echo "${NODE_SHA256}  ${TEMP_DIR}/node.tar.xz" | sha256sum --check --status
tar -xf "${TEMP_DIR}/node.tar.xz" -C "${TEMP_DIR}"
find "${TEMP_DIR}" -type f -name "node" -exec mv {} "${BINDIR}/" \;
chmod +x "${BINDIR}/node"

echo "[SUCCESS] All binaries verified and installed in ${BINDIR}"
