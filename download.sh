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

USER_AGENT_LIST=(
    "Mozilla/5.0 (X11; Linux x86_64; rv:146.0) Gecko/20100101 Firefox/146.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36 Edg/143.0.3650.96"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:146.0) Gecko/20100101 Firefox/146.0"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0"
)

# Pick a random User Agent from the list
RANDOM_USER_AGENT=${USER_AGENT_LIST[$RANDOM % ${#USER_AGENT_LIST[@]}]}

echo -e "${GREEN}[STEALTH] Identity assigned: $RANDOM_USER_AGENT${NC}"

echo -e "${GREEN}[INFO] Starting yt-dlp from portable environment...${NC}"

# 3. Run yt-dlp with portable paths
# Note: Added --restrict-filenames to prevent errors with special characters in filenames
"$BINDIR/yt-dlp" \
  --verbose \
  --user-agent "$RANDOM_USER_AGENT" \
  --referer "https://www.youtube.com/" \
  --sleep-requests 1.5 \
  --js-runtimes "node:${BINDIR}/node" \
  --ffmpeg-location "${BINDIR}/ffmpeg" \
  --concurrent-fragments 5 \
  -f "bv+(251/mergeall[format_id~=251-]/140/mergeall[format_id~=140-])/b" \
  --embed-thumbnail \
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
