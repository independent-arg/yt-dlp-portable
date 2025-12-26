# yt-dlp-portable

A shell wrapper for `yt-dlp` designed for portability.

## Prerequisites
This project requires the following binaries inside the `bin/` folder:
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [FFmpeg](https://github.com/yt-dlp/FFmpeg-Builds)
- [Node.js](https://nodejs.org) (for JS challenges)

> **Note:** An external JavaScript runtime (like Node.js or Deno) is now required for full YouTube support. yt-dlp uses it to solve JavaScript challenges presented by the platform. [Read more](https://github.com/yt-dlp/yt-dlp/issues/15012).

## Installation
1. **Clone this repository**:
```bash
git clone https://github.com/independent-arg/yt-dlp-portable.git
cd yt-dlp-portable
```
2. **Make scripts executable**:
```bash
chmod +x *.sh

```
3. **Run the setup script**:
This will download the required binaries to the `bin/` folder.
```bash
./setup.sh

```
*Wait for the process to finish. It will verify the hashes of the downloaded files.*

## Usage
Use the `download.sh` script to download videos. It acts as a wrapper for `yt-dlp`.
```bash
./download.sh "URL"
```

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


---

This script is a wrapper. All third-party tools (yt-dlp, FFmpeg, Node.js) belong to their respective owners and are subject to their own licenses.

---
