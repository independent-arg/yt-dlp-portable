#!/bin/bash
# yt-dlp-portable - independent_arg

# Get the absolute path of the script's directory
BASEDIR=$(dirname "$(readlink -f "$0")")

# Check if a URL was provided
if [ -z "$1" ]; then
    echo "Usage: ./download.sh [URL]"
    echo "Example: ./download.sh https://www.youtube.com/watch?v=1n2Z2YeKj7M"
    exit 1
fi

# Ensure the downloads directory exists
mkdir -p "$BASEDIR/downloads"

# Run yt-dlp with portable binary paths
"$BASEDIR/bin/yt-dlp" \
  --verbose \
  --js-runtimes "node:${BASEDIR}/bin/node" \
  --ffmpeg-location "${BASEDIR}/bin/ffmpeg" \
  --concurrent-fragments 5 \
  -P "$BASEDIR/downloads" \
  "$@"