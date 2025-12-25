# yt-dlp-portable

A shell wrapper for `yt-dlp` designed for portability.

## Prerequisites
This project requires the following binaries inside the `bin/` folder:
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [FFmpeg](https://github.com/yt-dlp/FFmpeg-Builds)
- [Node.js](https://nodejs.org) (for JS challenges)

> **Note:** An external JavaScript runtime (like Node.js or Deno) is now required for full YouTube support. yt-dlp uses it to solve JavaScript challenges presented by the platform. [Read more](https://github.com/yt-dlp/yt-dlp/issues/15012).

## Installation
1. Clone this repository.
2. Run setup.sh: this script will download and verify the correct versions of yt-dlp, FFmpeg, and Node.js into the bin/ folder.
```bash
chmod +x setup.sh
./setup.sh
```
3. Make the main script executable:: `chmod +x download.sh`.

```text
yt-dlp-portable/
├── download.sh      # Main execution script
├── setup.sh         # Environment provisioning & verification
├── bin/
│   ├── ffmpeg
│   ├── ffprobe
│   ├── node
│   └── yt-dlp
└── downloads/       # Automatically created
```

## Usage
```bash
./download.sh "URL"
```

---

This script is a wrapper. All third-party tools (yt-dlp, FFmpeg, Node.js) belong to their respective owners and are subject to their own licenses.

---