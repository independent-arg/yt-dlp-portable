# yt-dlp-portable

A portable, feature-rich shell wrapper for `yt-dlp` with interactive configuration menus and stealth features.

## Features

- **Interactive Menu System**: Configure all download options through an intuitive menu interface
- **Quick Mode**: Download with sensible defaults using `--quick` flag
- **Stealth Mode**: Intelligent request delays and automatic user-agent handling by yt-dlp.
- **Full Configuration**: Control format, quality, subtitles, thumbnails, filenames, and advanced options
- **Multiple URLs**: Download multiple videos in a single command
- **Portable**: All dependencies bundled in `bin/` directory
- **Security**: Prevents execution as root, validates downloads with SHA256 checksums

## Prerequisites
This project requires the following binaries inside the `bin/` folder:
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [FFmpeg](https://github.com/yt-dlp/FFmpeg-Builds)
- [Deno](https://github.com/denoland/deno) (for JS challenges)

> **Note:** An external JavaScript runtime (like Deno or Node.js) is now required for full YouTube support. yt-dlp uses it to solve JavaScript challenges presented by the platform. [Read more](https://github.com/yt-dlp/yt-dlp/issues/15012).

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
![setupsh](https://github.com/user-attachments/assets/bff44891-0431-44ef-a1e5-571e7c8ffb2f)
*Wait for the process to finish. It will verify the hashes of the downloaded files.*

## Usage

### Quick Mode (Recommended for Simple Downloads)

Download with default settings (best video+audio, embedded thumbnail, no subtitles):
```bash
./download.sh --quick "https://www.example.com/watch?v=example"
```

Or use the short flag:
```bash
./download.sh -q "https://www.example.com/watch?v=example"
```

### Interactive Mode

Launch the interactive configuration menu:
```bash
./download.sh "https://www.example.com/watch?v=example"
```
<img width="1576" height="520" alt="download" src="https://github.com/user-attachments/assets/e64f8052-a61b-43d3-bd40-5581d382ec88" />


The interactive menu allows you to configure:

1. **Subtitles**: Download, embed, or both (with language selection)
2. **Thumbnail**: Embed and convert to JPG/PNG, or don't embed
3. **Format & Quality**: 
   - Best video + best audio (recommended)
   - Best pre-merged format
   - Video only / Audio only
   - Specific quality (2160p, 1440p, 1080p, 720p, etc.)
   - Custom format
4. **Filename Template**: Choose from presets or create custom template
5. **Advanced Options**:
   - Verbose mode
   - Restrict filenames
   - Don't modify file date
   - Concurrent fragments (1-10)
   - Sleep time between requests

### Multiple URLs

Download multiple videos at once:
```bash
./download.sh --quick "URL1" "URL2" "URL3"
```

### Help

Show usage information:
```bash
./download.sh --help
# or
./download.sh -h
```
## Default Configuration (Quick Mode)

When using `--quick` or `-q`, the following defaults are applied:

- **Format**: Best video + best audio (merged)
- **Thumbnail**: Embedded and converted to JPG
- **Subtitles**: Not downloaded
- **Output Template**: `%(title)s [%(id)s].%(ext)s`
- **Verbose Mode**: Enabled
- **Restrict Filenames**: Enabled (sanitizes filenames for compatibility)
- **No Modify Date**: Enabled (preserves original file date)
- **Concurrent Fragments**: 5
- **Sleep Requests**: 1.5 seconds
- **User Agent**: Random (stealth mode)

## Project Structure

```text
yt-dlp-portable/
├── download.sh      # Main execution script with interactive menus
├── setup.sh         # Environment provisioning & verification
├── bin/
│   ├── deno         # JavaScript runtime for YouTube challenges
│   ├── ffmpeg       # Video/audio processing
│   ├── ffprobe      # Media information
│   └── yt-dlp       # Video downloader
├── .gitignore
└── README.md
```
## Supported Platforms

- YouTube (youtube.com, youtu.be)
- Vimeo
- Dailymotion
- Twitch
- And all other platforms supported by yt-dlp

## Troubleshooting

### Binary not found
If you see "Binary not found" errors, run:
```bash
./setup.sh
```

### Permission denied
Make sure scripts are executable:
```bash
chmod +x *.sh
```

### Download fails
- Check your internet connection
- Verify the URL is valid and accessible
- Try using verbose mode to see detailed error messages
- Some videos may be region-locked or require authentication

## License

This script is a wrapper. All third-party tools (yt-dlp, FFmpeg, deno) belong to their respective owners and are subject to their own licenses.

---

**Note**: This project is designed for Linux x86_64 systems. The setup script will warn you if you're running on a different architecture.
