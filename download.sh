#!/bin/bash
# yt-dlp-portable - download.sh

# Strict mode: stops execution on errors, undefined variables, or pipe failures
set -euo pipefail

# Function to handle interruptions (Ctrl+C)
trap 'echo -e "\n${YELLOW}[INFO] Download interrupted by user.${NC}"; exit 130' INT

# Robustly get the absolute path of the script directory
if command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
    BASEDIR=$(dirname "$(readlink -f "$0")")
else
    # Fallback for systems without readlink -f (macOS, BSD)
    BASEDIR=$(cd "$(dirname "$0")" && pwd -P)
fi
BINDIR="$BASEDIR/bin"

# Colors for messages
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Security: Prevent execution as root
if [ "$EUID" -eq 0 ]; then
    echo -e "${RED}[ERROR] Please do not run this script as root.${NC}"
    echo -e "${RED}This script does not require root privileges and running as root is a security risk.${NC}"
    exit 1
fi

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
check_binary "deno"
check_binary "ffmpeg"
check_binary "ffprobe"

# 2. Check if a URL or arguments were provided
if [ $# -eq 0 ]; then
    echo -e "${RED}Error: No arguments provided.${NC}"
    echo "Usage: ./download.sh [URL] [OPTIONS]"
    echo "Example: ./download.sh https://www.youtube.com/watch?v=XXXXXX"
    exit 1
fi

# Function to get a random number (using urandom if available)
random_num() {
    local min=$1
    local max=$2
    local rand
    if [[ -r /dev/urandom ]]; then
        rand=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
        echo $((min + (rand % (max - min + 1))))
    else
        echo $((min + (RANDOM % (max - min + 1))))
    fi
}

# Generate random user agent
generate_random_user_agent() {
    local chrome_major
    local firefox_ver
    local os
    local chrome_ver
    
    chrome_major=$(random_num 137 143)
    firefox_ver=$(random_num 140 146)
    os=$(random_num 1 3)
    
    case $chrome_major in
        137) 
            local versions=("137.0.7151.68")
            chrome_ver="${versions[0]}"
            ;;
        138) 
            local versions=("138.0.7204.49" "138.0.7204.50")
            chrome_ver="${versions[$(random_num 0 1)]}"
            ;;
        139) 
            local versions=("139.0.7260.40")
            chrome_ver="${versions[0]}"
            ;;
        140) 
            local versions=("140.0.7339.128")
            chrome_ver="${versions[0]}"
            ;;
        141) 
            local versions=("141.0.7390.54" "141.0.7390.55")
            chrome_ver="${versions[$(random_num 0 1)]}"
            ;;
        142) 
            local versions=("142.0.7444.59" "142.0.7444.60")
            chrome_ver="${versions[$(random_num 0 1)]}"
            ;;
        143) 
            local versions=("143.0.7499.40" "143.0.7499.41")
            chrome_ver="${versions[$(random_num 0 1)]}"
            ;;
    esac
    
    case $os in
        1) local os_str="Windows NT 10.0; Win64; x64" ;;
        2) local os_str="X11; Linux x86_64" ;;
        3) local os_str="Macintosh; Intel Mac OS X 26_0" ;;
    esac
    
    case $(random_num 1 2) in
        1) echo "Mozilla/5.0 ($os_str) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${chrome_ver} Safari/537.36" ;;
        2) echo "Mozilla/5.0 ($os_str; rv:${firefox_ver}.0) Gecko/20100101 Firefox/${firefox_ver}.0" ;;
    esac
}

# Pick a random User Agent from the list
RANDOM_USER_AGENT=$(generate_random_user_agent)

echo -e "${GREEN}[STEALTH] Identity assigned: $RANDOM_USER_AGENT${NC}"

echo -e "${GREEN}[INFO] Starting yt-dlp from portable environment...${NC}"

# 3. Run yt-dlp with portable paths
# Note: Added --restrict-filenames to prevent errors with special characters in filenames
"$BINDIR/yt-dlp" \
  --verbose \
  --user-agent "$RANDOM_USER_AGENT" \
  --referer "https://www.youtube.com/" \
  --sleep-requests 1.5 \
  --js-runtimes "deno:${BINDIR}/deno" \
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
