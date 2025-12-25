#!/bin/bash
# yt-dlp-portable - download.sh

# Strict mode: stops execution on errors, undefined variables, or pipe failures
set -euo pipefail

# Function to handle interruptions (Ctrl+C)
trap 'echo -e "\n[INFO] Download interrupted by user."; exit 130' INT

# Robustly get the absolute path of the script directory
BASEDIR=$(dirname "$(readlink -f "$0")")
BINDIR="$BASEDIR/bin"

# Colors for messages (optional, improves readability)
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Function to verify binaries and permissions
check_binary() {
    local bin_name="$1"
    local bin_path="$BINDIR/$bin_name"

    if [ ! -f "$bin_path" ]; then
        echo -e "${RED}[ERROR] Binary not found: $bin_name${NC}"
        echo "Please run: bash setup.sh"
        exit 1
    fi

    if [ ! -x "$bin_path" ]; then
        echo "[WARN] Fixing execution permissions for $bin_name..."
        chmod +x "$bin_path"
    fi
}

# 1. Verify all required binaries
check_binary "yt-dlp"
check_binary "node"
check_binary "ffmpeg"
check_binary "ffprobe"

# 2. Check if a URL or arguments were provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No arguments provided.${NC}"
    echo "Usage: ./download.sh [URL] [OPTIONS]"
    echo "Example: ./download.sh https://www.youtube.com/watch?v=XXXXXX"
    exit 1
fi

echo -e "${GREEN}[INFO] Starting yt-dlp from portable environment...${NC}"

# 3. Run yt-dlp with portable paths
# Note: Added --restrict-filenames to prevent errors with special characters in filenames
"$BINDIR/yt-dlp" \
  --verbose \
  --js-runtimes "node:${BINDIR}/node" \
  --ffmpeg-location "${BINDIR}/ffmpeg" \
  --concurrent-fragments 5 \
  -f "bv+(251/mergeall[format_id~=251-]/140/mergeall[format_id~=140-])/b" \
  --write-thumbnail \
  --convert-thumbnails jpg \
  --restrict-filenames \
  --output "%(title)s [%(id)s].%(ext)s" \
  --no-mtime \
  "$@"

exit_code=$?

if [ $exit_code -eq 0 ]; then
    echo -e "${GREEN}[SUCCESS] Process finished successfully.${NC}"
else
    echo -e "${RED}[FAILURE] yt-dlp finished with error code: $exit_code${NC}"
    exit $exit_code
fi
