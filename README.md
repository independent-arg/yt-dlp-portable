# yt-dlp-portable

A robust, portable, and interactive shell wrapper for `yt-dlp`.
Designed to make video downloading simple, secure, and fully configurable without polluting your system.

## Key Features

- **Zero Global Dependencies - Portable**: Automatically manages `yt-dlp`, `FFmpeg`, and `Deno` inside a local `bin/` folder.
- **Interactive Menu**: Guided configuration for quality, formats, subtitles, and post-processing.
- **Flexible URL Input**: Provide URLs via command line or enter them interactively within the menu
- **Smart Review**: Presents a clear summary of your settings (Content, Visuals, Data) before you hit download.
- **Quick Mode**: One-command instant download using optimized "Best Quality" defaults `--quick`.
- **Modern Support**: Includes `Deno` runtime to handle complex JavaScript challenges from sites like YouTube.
- **Hardened Security**: Strict SHA256 binary verification, root-execution prevention, and safe temporary file handling.

## Prerequisites

To run this project, your system must meet the following requirements:
- **OS**: Linux (x86_64 architecture).
- **Disk Space**: At least **1GB** of available space for binaries and temporary processing.
- **Tools**: `curl`, `tar`, `unzip`, and `sha256sum` (standard on most Linux distros).

This project requires the following binaries inside the `bin/` folder:
- [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- [FFmpeg](https://github.com/yt-dlp/FFmpeg-Builds)
- [Deno](https://github.com/denoland/deno) (for JS challenges)

> **Note:** An external JavaScript runtime (Deno) is integrated into this project to solve JavaScript challenges presented by platforms like YouTube. [Read more](https://github.com/yt-dlp/yt-dlp/issues/15012).

## Installation

1. **Clone this repository**:
```bash
git clone https://github.com/independent-arg/yt-dlp-portable.git
cd yt-dlp-portable
```

2. **Grant execution permissions**:
```bash
chmod +x *.sh
```

3. **Run the setup script**:
```bash
./setup.sh
```
*This will automatically download and verify the latest binaries (yt-dlp, FFmpeg, Deno) into the `bin/` directory.*

## Usage

### Interactive Mode (Guided)
Launch the menu to configure every aspect of your download.
```bash
./download.sh
```
You can also pass URLs as arguments to skip the URL manager:
```bash
./download.sh "https://youtu.be/example"
```

### Quick Mode (Fastest)
Skip the menus and download immediately with **Best Video + Best Audio** settings.
```bash
./download.sh --quick "https://youtu.be/example"
# or
./download.sh -q "https://youtu.be/example"
```

*This mode uses optimized defaults: Best quality, MKV container, and embedded JPG thumbnails.*

### Batch Downloads

Download multiple videos or playlists in one go.

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

## Interactive Menu Options

The interactive menu allows you to configure:

1. **Manage URLs**: Add, clear, and list the URLs to be downloaded.
2. **Configure Output Directory**: Set a custom folder (persisted between sessions).
3. **Subtitles**: Download, embed, or both (with language selection).
4. **Thumbnail**: Embed and convert to JPG/PNG, or disable embedding.
5. **Metadata & Chapters**: Embed video metadata, chapter markers, and complete info.json.
6. **Format & Quality**: 
   - Best quality (Best Video + Best Audio)
   - Specific resolution (e.g., 1080p, 720p)
   - Video only / Audio only
   - Remux to specific container (MP4, MKV, WebM, etc.)
   - Custom format
7. **Audio Extraction**: Convert to MP3, AAC, OPUS, FLAC, M4A, VORBIS, or WAV.
8. **Playlist Handling**:
   - Single video mode, entire playlist, or specific ranges.
   - Reverse order and folder organization.
9. **Download Archive**: Avoid duplicates using a tracking file.
10. **Output filename**: Choose from presets or create custom templates.
11. **Advanced Options**:
   - Verbose mode, ASCII filenames, and original date preservation.
   - Concurrent fragments and request sleep timers.
12. **View Current Configuration**: Review all settings before execution.
13. **Check for Updates**: Re-run the setup process to update binaries.

## Project Structure

```text
yt-dlp-portable/
├── download.sh      # Main downloader wrapper
├── setup.sh         # Environment provisioning & verification
├── bin/             # Local binaries (managed by setup.sh)
│   ├── deno
│   ├── ffmpeg
│   ├── ffprobe
│   └── yt-dlp
└── README.md
```
## Supported Platforms

- YouTube
- Twitch
- And all other platforms supported by yt-dlp

## Troubleshooting

- Binary not found: Run `./setup.sh` to reinstall components.
- Permission denied: Run `chmod +x *.sh`

#### Download fails
- Check your internet connection.
- Ensure you have free space.
- Try **Verbose mode** in Advanced Options to see detailed error logs.
- Some videos may be region-locked or require authentication
- For YouTube errors, ensure `setup.sh` completed successfully to install Deno.

## License

This project is a wrapper script. The downloaded binaries (`yt-dlp`, `FFmpeg`, `Deno`) are subject to their respective licenses.

---

**Note**: This project is designed for Linux x86_64 systems.
