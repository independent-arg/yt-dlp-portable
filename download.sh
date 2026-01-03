#!/bin/bash

# ==============================================================================
# Script Name: yt-dlp-portable (download.sh)
# Version:     v0.6.3(testing)
# Author:      independent-arg
# License:     MIT
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONSTANTS & METADATA
# ==============================================================================

readonly VERSION="v0.6.3(testing)"
readonly LAST_UPDATED="2025-01-02"

# ==============================================================================
# SIGNAL HANDLERS
# ==============================================================================

# Function to handle interruptions (Ctrl+C)
trap 'echo -e "\n${YELLOW}[INFO] Download interrupted by user.${NC}"; exit 130' INT

# ==============================================================================
# PATH RESOLUTION
# ==============================================================================

# Robustly get the absolute path of the script directory
if command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
    BASEDIR=$(dirname "$(readlink -f "$0")")
else
    # Fallback for systems without readlink -f (macOS, BSD)
    BASEDIR=$(cd "$(dirname "$0")" && pwd -P)
fi
BINDIR="$BASEDIR/bin"

# ==============================================================================
# UI CONSTANTS
# ==============================================================================

# Colors for messages
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==============================================================================
# SYSTEM VALIDATION FUNCTIONS
# ==============================================================================

# Security: Prevent execution as root
check_root() {
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}[ERROR] Please do not run this script as root.${NC}"
        echo -e "${RED}This script does not require root privileges and running as root is a security risk.${NC}"
        exit 1
    fi
}

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
        echo -e "${YELLOW}[WARN] Fixing execution permissions for $bin_name...${NC}"
        chmod +x "$bin_path"
    fi
}

# Check disk space before download
check_disk_space() {
    local available
    available=$(df -P . | awk 'NR==2 {print $4}')
    local available_mb=$((available / 1024))

    if [ "$available" -lt 1048576 ]; then  # Less than 1GB
        echo -e "${YELLOW}[WARN] Low disk space: ${available_mb}MB available${NC}"
        echo -e "${YELLOW}Large downloads may fail. Consider freeing up space.${NC}"
        read -rp "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Download cancelled by user.${NC}"
            exit 0
        fi
    fi
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Default options and quick mode
declare -A OPTIONS
OPTIONS[format]="bestvideo*+bestaudio/best"
OPTIONS[extract_audio]="no"
OPTIONS[audio_format]=""
OPTIONS[audio_quality]="5"
OPTIONS[embed_thumbnail]="yes"
OPTIONS[convert_thumbnails]="jpg"
OPTIONS[merge_output_format]="mkv"
OPTIONS[subtitles]="no"
OPTIONS[subtitles_lang]=""
OPTIONS[embed_subs]="no"
OPTIONS[embed_metadata]="no"
OPTIONS[embed_chapters]="no"
OPTIONS[embed_info_json]="no"
OPTIONS[remux_video]=""
OPTIONS[write_subs]="no"
OPTIONS[output_template]="%(title)s [%(id)s].%(ext)s"
OPTIONS[verbose]="yes"
OPTIONS[restrict_filenames]="yes"
OPTIONS[no_mtime]="yes"
OPTIONS[concurrent_fragments]="5"
OPTIONS[sleep_requests]="1.5"

# ==============================================================================
# MENU FUNCTIONS
# ==============================================================================

show_subtitles_menu() {
    echo ""
    echo -e "${YELLOW}=== Subtitles Configuration ==="
    echo -e "${NC}1) Don't download subtitles (default)"
    echo "2) Download subtitles (separate .srt file)"
    echo "3) Embed subtitles into video file"
    echo "4) Download and embed subtitles"
    echo "5) Back to main menu"
    echo ""
    read -rp "Select an option [1-5]: " sub_choice
    
    case $sub_choice in
        1)
            OPTIONS[subtitles]="no"
            OPTIONS[write_subs]="no"
            OPTIONS[embed_subs]="no"
            echo -e "${GREEN}✓ Subtitles disabled${NC}"
            ;;
        2)
            OPTIONS[subtitles]="yes"
            OPTIONS[write_subs]="yes"
            OPTIONS[embed_subs]="no"
            echo ""
            read -rp "Subtitle language (e.g., en, es, en+es) [Enter for all]: " sub_lang
            # Sanitize: allow alphanumeric, +, -, and comma
            sub_lang=$(echo "${sub_lang:-all}" | tr -cd 'a-zA-Z0-9+,-')
            if [[ -z "$sub_lang" ]]; then
                sub_lang="all"
            fi
            OPTIONS[subtitles_lang]="$sub_lang"
            echo -e "${GREEN}✓ Will download subtitles: $sub_lang${NC}"
            ;;
        3)
            OPTIONS[subtitles]="yes"
            OPTIONS[write_subs]="no"
            OPTIONS[embed_subs]="yes"
            echo ""
            read -rp "Subtitle language (e.g., en, es, en+es) [Enter for all]: " sub_lang
            # Sanitize: allow alphanumeric, +, -, and comma
            sub_lang=$(echo "${sub_lang:-all}" | tr -cd 'a-zA-Z0-9+,-')
            if [[ -z "$sub_lang" ]]; then
                sub_lang="all"
            fi
            OPTIONS[subtitles_lang]="$sub_lang"
            echo -e "${GREEN}✓ Will embed subtitles: $sub_lang${NC}"
            ;;
        4)
            OPTIONS[subtitles]="yes"
            OPTIONS[write_subs]="yes"
            OPTIONS[embed_subs]="yes"
            echo ""
            read -rp "Subtitle language (e.g., en, es, en+es) [Enter for all]: " sub_lang
            # Sanitize: allow alphanumeric, +, -, and comma
            sub_lang=$(echo "${sub_lang:-all}" | tr -cd 'a-zA-Z0-9+,-')
            if [[ -z "$sub_lang" ]]; then
                sub_lang="all"
            fi
            OPTIONS[subtitles_lang]="$sub_lang"
            echo -e "${GREEN}✓ Will download and embed subtitles: $sub_lang${NC}"
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

show_thumbnail_menu() {
    echo ""
    echo -e "${YELLOW}=== Thumbnail Configuration ==="
    echo -e "${NC}1) Embed thumbnail as JPG (recommended, forces MKV container, default)"
    echo "2) Embed thumbnail in original format"
    echo "3) Embed thumbnail as PNG"
    echo "4) Don't embed thumbnail"
    echo "5) Back to main menu"
    echo ""
    read -rp "Select an option [1-5]: " thumb_choice
    
    case $thumb_choice in
        1)
            OPTIONS[embed_thumbnail]="yes"
            OPTIONS[convert_thumbnails]="jpg"
            OPTIONS[merge_output_format]="mkv"
            echo -e "${GREEN}✓ Will embed JPG thumbnail (output will be MKV)${NC}"
            ;;
        2)
            OPTIONS[embed_thumbnail]="yes"
            OPTIONS[convert_thumbnails]=""
            OPTIONS[merge_output_format]=""
            echo -e "${GREEN}✓ Will embed thumbnail (original format)${NC}"
            ;;
        3)
            OPTIONS[embed_thumbnail]="yes"
            OPTIONS[convert_thumbnails]="png"
            OPTIONS[merge_output_format]=""
            echo -e "${GREEN}✓ Will embed thumbnail as PNG${NC}"
            ;;
        4)
            OPTIONS[embed_thumbnail]="no"
            OPTIONS[convert_thumbnails]=""
            OPTIONS[merge_output_format]=""
            echo -e "${GREEN}✓ Thumbnail disabled${NC}"
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

show_metadata_menu() {
    echo ""
    echo -e "${YELLOW}=== Metadata and Chapters ==="
    echo -e "${NC}1) Don't embed any metadata (default)"
    echo "2) Embed basic metadata (title, artist, date)"
    echo "3) Embed metadata + chapter markers"
    echo "4) Embed everything (metadata + chapters + full info.json for MKV)"
    echo "5) Back to main menu"
    echo ""
    read -rp "Select an option [1-5]: " meta_choice
    
    case $meta_choice in
        1)
            OPTIONS[embed_metadata]="no"
            OPTIONS[embed_chapters]="no"
            OPTIONS[embed_info_json]="no"
            echo -e "${GREEN}✓ Metadata disabled${NC}"
            ;;
        2)
            OPTIONS[embed_metadata]="yes"
            OPTIONS[embed_chapters]="no"
            OPTIONS[embed_info_json]="no"
            echo -e "${GREEN}✓ Will embed basic metadata (title, artist, date, description)${NC}"
            ;;
        3)
            OPTIONS[embed_metadata]="yes"
            OPTIONS[embed_chapters]="yes"
            OPTIONS[embed_info_json]="no"
            echo -e "${GREEN}✓ Will embed metadata with chapter markers${NC}"
            ;;
        4)
            OPTIONS[embed_metadata]="yes"
            OPTIONS[embed_chapters]="yes"
            OPTIONS[embed_info_json]="yes"
            echo -e "${GREEN}✓ Will embed all metadata (note: info.json only works with MKV/MKA)${NC}"
            echo -e "${YELLOW}   Info: This option embeds the complete JSON metadata as attachment${NC}"
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

show_format_menu() {
    echo ""
    echo -e "${YELLOW}=== Format and Quality ==="
    echo -e "${NC}1) Highest quality available (recommended, default)"
    echo "   Downloads and merges best video with best audio"
    echo "2) Best pre-merged format (single file, faster, usually lower quality)"
    echo "   Single pre-merged file from the server"
    echo "3) Video only (no sound)"
    echo "4) Audio only (no video, no conversion)"
    echo "5) Specific resolution (4K, 1080p, 720p, etc.)"
    echo "6) Remux video to specific container (fast, no re-encoding)"
    echo "7) Custom format (advanced)"
    echo "8) Back to main menu"
    echo ""
    read -rp "Select an option [1-8]: " format_choice
    
    case $format_choice in
        1)
            OPTIONS[format]="bestvideo*+bestaudio/best"
            echo -e "${GREEN}✓ Format: Best video + best audio (Recommended)${NC}"
            ;;
        2)
            OPTIONS[format]="best"
            echo -e "${GREEN}✓ Format: Best (quick download)${NC}"
            ;;
        3)
            OPTIONS[format]="bestvideo"
            echo -e "${GREEN}✓ Format: Video only${NC}"
            ;;
        4)
            OPTIONS[format]="bestaudio"
            echo -e "${GREEN}✓ Format: Audio only${NC}"
            ;;
        5)
            echo ""
            echo "Available options: 2160p, 1440p, 1080p, 720p, 480p, 360p, 240p, 144p"
            read -rp "Select quality (e.g., 1080p): " quality
            # Sanitize input: remove any non-alphanumeric characters except 'p'
            quality=$(echo "$quality" | tr -cd '0-9p')
            if [[ -n "$quality" && "$quality" =~ ^[0-9]+p?$ ]]; then
                # Remove 'p' if present for height calculation
                height_num=$(echo "$quality" | tr -d 'p')
                OPTIONS[format]="bestvideo[height<=${height_num}]+bestaudio/best[height<=${height_num}]"
                echo -e "${GREEN}✓ Format: Up to ${height_num}p${NC}"
            else
                echo -e "${RED}Invalid quality format. Using default.${NC}"
            fi
            ;;
        6)
            echo ""
            echo -e "${YELLOW}Remux changes the container without re-encoding (fast, no quality loss)${NC}"
            echo "Available containers: mp4, mkv, webm, avi, flv, mov"
            echo "Note: If the source codec is incompatible with the container, remux will fail"
            read -rp "Target container format: " remux_format
            # Sanitize: allow only alphanumeric
            remux_format=$(echo "$remux_format" | tr -cd 'a-z0-9')
            
            if [[ -n "$remux_format" ]]; then
                # We'll add this to execution later, but store it now
                OPTIONS[remux_video]="$remux_format"
                echo -e "${GREEN}✓ Will remux video to ${remux_format} container${NC}"
                echo -e "${YELLOW}   Info: Still downloading best quality, will remux after${NC}"
            else
                echo -e "${RED}Invalid format. No remux will be applied.${NC}"
                OPTIONS[remux_video]=""
            fi
            ;;
        7)
            echo ""
            echo -e "${YELLOW}Custom format (see yt-dlp documentation)${NC}"
            echo -e "${YELLOW}Warning: Invalid formats may cause download failures.${NC}"
            read -rp "Format: " custom_format
            if [[ -n "$custom_format" ]]; then
                # Basic sanitization: remove dangerous characters but allow yt-dlp format syntax
                custom_format=$(echo "$custom_format" | tr -cd 'a-zA-Z0-9+\-/\[\]\(\)=<>:')
                OPTIONS[format]="$custom_format"

                if [[ -z "$custom_format" ]]; then
                    echo -e "${RED}Invalid characters detected. Using default format.${NC}"
                    OPTIONS[format]="bestvideo+bestaudio/best"
                else
                    OPTIONS[format]="$custom_format"
                    echo -e "${GREEN}✓ Format: $custom_format${NC}"
                fi
            fi
            ;;
        8)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

show_audio_menu() {
    echo ""
    echo -e "${YELLOW}=== Audio Extraction and Conversion ==="
    echo -e "${NC}This menu is for extracting/converting audio from videos."
    echo "If you just want to download audio streams without conversion,"
    echo "use the Format menu instead and select 'Audio stream only'."
    echo ""
    echo "1) Don't extract/convert audio (default)"
    echo "2) Extract audio as MP3 (most compatible)"
    echo "3) Extract audio as AAC (good quality, smaller files)"
    echo "4) Extract audio as OPUS (best quality/size ratio)"
    echo "5) Extract audio as FLAC (lossless, larger files)"
    echo "6) Extract audio as M4A (Apple ecosystem)"
    echo "7) Extract audio as VORBIS (OGG container)"
    echo "8) Extract audio as WAV (uncompressed, very large)"
    echo "9) Custom audio format and quality (advanced)"
    echo "10) Back to main menu"
    echo ""
    read -rp "Select an option [1-10]: " audio_choice
    
    case $audio_choice in
        1)
            OPTIONS[extract_audio]="no"
            OPTIONS[audio_format]=""
            echo -e "${GREEN}✓ Audio extraction disabled${NC}"
            ;;
        2)
            OPTIONS[extract_audio]="yes"
            OPTIONS[audio_format]="mp3"
            echo ""
            read -rp "Audio quality [0-9, where 0=best, 5=default, 9=worst] or bitrate (e.g., 192K): " quality
            # Sanitize: allow digits, 'K', 'M', and decimal point
            quality=$(echo "${quality:-5}" | tr -cd '0-9KMkm.')
            if [[ -z "$quality" ]]; then
                quality="5"
            fi
            OPTIONS[audio_quality]="$quality"
            echo -e "${GREEN}✓ Will extract audio as MP3 with quality: ${quality}${NC}"
            ;;
        3)
            OPTIONS[extract_audio]="yes"
            OPTIONS[audio_format]="aac"
            echo ""
            read -rp "Audio quality [0-9, where 0=best, 5=default, 9=worst] or bitrate (e.g., 192K): " quality
            quality=$(echo "${quality:-5}" | tr -cd '0-9KMkm.')
            if [[ -z "$quality" ]]; then
                quality="5"
            fi
            OPTIONS[audio_quality]="$quality"
            echo -e "${GREEN}✓ Will extract audio as AAC with quality: ${quality}${NC}"
            ;;
        4)
            OPTIONS[extract_audio]="yes"
            OPTIONS[audio_format]="opus"
            echo ""
            read -rp "Audio quality [0-9, where 0=best, 5=default, 9=worst] or bitrate (e.g., 128K): " quality
            quality=$(echo "${quality:-5}" | tr -cd '0-9KMkm.')
            if [[ -z "$quality" ]]; then
                quality="5"
            fi
            OPTIONS[audio_quality]="$quality"
            echo -e "${GREEN}✓ Will extract audio as OPUS with quality: ${quality}${NC}"
            echo -e "${YELLOW}   Info: OPUS offers excellent quality at lower bitrates${NC}"
            ;;
        5)
            OPTIONS[extract_audio]="yes"
            OPTIONS[audio_format]="flac"
            OPTIONS[audio_quality]="0"
            echo -e "${GREEN}✓ Will extract audio as FLAC (lossless)${NC}"
            echo -e "${YELLOW}   Info: FLAC files are large but preserve perfect quality${NC}"
            ;;
        6)
            OPTIONS[extract_audio]="yes"
            OPTIONS[audio_format]="m4a"
            echo ""
            read -rp "Audio quality [0-9, where 0=best, 5=default, 9=worst] or bitrate (e.g., 192K): " quality
            quality=$(echo "${quality:-5}" | tr -cd '0-9KMkm.')
            if [[ -z "$quality" ]]; then
                quality="5"
            fi
            OPTIONS[audio_quality]="$quality"
            echo -e "${GREEN}✓ Will extract audio as M4A with quality: ${quality}${NC}"
            ;;
        7)
            OPTIONS[extract_audio]="yes"
            OPTIONS[audio_format]="vorbis"
            echo ""
            read -rp "Audio quality [0-9, where 0=best, 5=default, 9=worst]: " quality
            quality=$(echo "${quality:-5}" | tr -cd '0-9')
            if [[ -z "$quality" ]]; then
                quality="5"
            fi
            OPTIONS[audio_quality]="$quality"
            echo -e "${GREEN}✓ Will extract audio as VORBIS with quality: ${quality}${NC}"
            ;;
        8)
            OPTIONS[extract_audio]="yes"
            OPTIONS[audio_format]="wav"
            OPTIONS[audio_quality]="0"
            echo -e "${GREEN}✓ Will extract audio as WAV (uncompressed)${NC}"
            echo -e "${YELLOW}   Warning: WAV files are very large${NC}"
            ;;
        9)
            echo ""
            echo -e "${YELLOW}Available formats: best, aac, alac, flac, m4a, mp3, opus, vorbis, wav${NC}"
            read -rp "Audio format: " custom_format
            # Sanitize: allow only alphanumeric
            custom_format=$(echo "$custom_format" | tr -cd 'a-zA-Z')
            
            if [[ -n "$custom_format" ]]; then
                OPTIONS[extract_audio]="yes"
                OPTIONS[audio_format]="$custom_format"
                echo ""
                read -rp "Audio quality [0-9 or bitrate like 192K]: " quality
                quality=$(echo "${quality:-5}" | tr -cd '0-9KMkm.')
                if [[ -z "$quality" ]]; then
                    quality="5"
                fi
                OPTIONS[audio_quality]="$quality"
                echo -e "${GREEN}✓ Will extract audio as ${custom_format} with quality: ${quality}${NC}"
            else
                echo -e "${RED}Invalid format. Audio extraction disabled.${NC}"
                OPTIONS[extract_audio]="no"
            fi
            ;;
        10)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

show_output_menu() {
    echo ""
    echo -e "${YELLOW}=== Output Filename Template ==="
    echo -e "${NC}1) Title [VideoID].ext (default)"
    echo "2) Title only.ext"
    echo "3) VideoID only.ext"
    echo "4) Title - ChannelName [VideoID].ext"
    echo "5) Custom template"
    echo "6) Back to main menu"
    echo ""
    read -rp "Select an option [1-6]: " output_choice
    
    case $output_choice in
        1)
            OPTIONS[output_template]="%(title)s [%(id)s].%(ext)s"
            echo -e "${GREEN}✓ Template: Title [ID].ext${NC}"
            ;;
        2)
            OPTIONS[output_template]="%(title)s.%(ext)s"
            echo -e "${GREEN}✓ Template: Title.ext${NC}"
            ;;
        3)
            OPTIONS[output_template]="%(id)s.%(ext)s"
            echo -e "${GREEN}✓ Template: ID.ext${NC}"
            ;;
        4)
            OPTIONS[output_template]="%(title)s - %(uploader)s [%(id)s].%(ext)s"
            echo -e "${GREEN}✓ Template: Title - Channel [ID].ext${NC}"
            ;;
        5)
            echo ""
            echo -e "${YELLOW}Custom template (see yt-dlp documentation)${NC}"
            echo "Examples: %(title)s, %(id)s, %(uploader)s, %(upload_date)s"
            read -rp "Template: " custom_template
            if [[ -n "$custom_template" ]]; then
                # Basic sanitization: remove newlines and carriage returns
                custom_template=$(echo "$custom_template" | tr -d '\n\r')
                OPTIONS[output_template]="$custom_template"
                echo -e "${GREEN}✓ Custom template applied${NC}"
            fi
            ;;
        6)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

show_advanced_menu() {
    echo ""
    echo -e "${YELLOW}=== Advanced Options ==="
    echo -e "${NC}1) Verbose mode: $([ "${OPTIONS[verbose]}" == "yes" ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
    echo "2) Restrict filenames (ASCII only, remove special chars): $([ "${OPTIONS[restrict_filenames]}" == "yes" ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
    echo "3) Preserve original upload date: $([ "${OPTIONS[no_mtime]}" == "yes" ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
    echo "4) Concurrent fragments: ${OPTIONS[concurrent_fragments]}"
    echo "5) Sleep between requests: ${OPTIONS[sleep_requests]}s"
    echo "6) Back to main menu"
    echo ""
    read -rp "Select an option [1-6]: " adv_choice
    
    case $adv_choice in
        1)
            if [ "${OPTIONS[verbose]}" == "yes" ]; then
                OPTIONS[verbose]="no"
                echo -e "${YELLOW}✓ Verbose mode disabled${NC}"
            else
                OPTIONS[verbose]="yes"
                echo -e "${GREEN}✓ Verbose mode enabled${NC}"
            fi
            show_advanced_menu
            ;;
        2)
            if [ "${OPTIONS[restrict_filenames]}" == "yes" ]; then
                OPTIONS[restrict_filenames]="no"
                echo -e "${YELLOW}✓ Filename restrictions disabled${NC}"
            else
                OPTIONS[restrict_filenames]="yes"
                echo -e "${GREEN}✓ Filename restrictions enabled${NC}"
            fi
            show_advanced_menu
            ;;
        3)
            if [ "${OPTIONS[no_mtime]}" == "yes" ]; then
                OPTIONS[no_mtime]="no"
                echo -e "${YELLOW}✓ Will preserve original file date${NC}"
            else
                OPTIONS[no_mtime]="yes"
                echo -e "${GREEN}✓ Won't modify file date${NC}"
            fi
            show_advanced_menu
            ;;
        4)
            echo ""
            read -rp "Number of concurrent fragments [1-10]: " fragments

            # Sanitize: only digits
            fragments=$(echo "$fragments" | tr -cd '0-9')

            if [[ -z "$fragments" ]]; then
                echo -e "${RED}Invalid input. Keeping current value: ${OPTIONS[concurrent_fragments]}${NC}"
            elif [ "$fragments" -lt 1 ] || [ "$fragments" -gt 10 ]; then
                echo -e "${RED}Value must be between 1 and 10. Keeping current value: ${OPTIONS[concurrent_fragments]}${NC}"
            else
                OPTIONS[concurrent_fragments]="$fragments"
                echo -e "${GREEN}✓ Updated to: $fragments${NC}"
            fi
            show_advanced_menu
            ;;
        5)
            echo ""
            read -rp "Sleep time in seconds (e.g., 1.5): " sleep_time
            # Sanitize: allow digits and one decimal point
            sleep_time=$(echo "$sleep_time" | tr -cd '0-9.')

            # Validate format: number with optional decimal, must be positive
            if [[ -z "$sleep_time" ]]; then
                echo -e "${RED}Invalid input. Keeping current value: ${OPTIONS[sleep_requests]}s${NC}"
            elif [[ ! "$sleep_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                echo -e "${RED}Invalid format. Keeping current value: ${OPTIONS[sleep_requests]}s${NC}"
            elif [[ "$sleep_time" == "0" || "$sleep_time" == "0.0" || "$sleep_time" == "0." ]]; then
                echo -e "${RED}Value must be greater than 0. Keeping current value: ${OPTIONS[sleep_requests]}s${NC}"
            else
                OPTIONS[sleep_requests]="$sleep_time"
                echo -e "${GREEN}✓ Updated to: ${sleep_time}s${NC}"
            fi
            show_advanced_menu
            ;;
        6)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            show_advanced_menu
            ;;
    esac
}

show_current_config() {
    echo ""
    echo -e "${GREEN}=== Current Configuration ===${NC}"
    echo ""
    echo -e "${BLUE}Format:${NC} ${OPTIONS[format]}"
    echo -e "${BLUE}Thumbnail:${NC} $([ "${OPTIONS[embed_thumbnail]}" == "yes" ] && echo "Embed$([ -n "${OPTIONS[convert_thumbnails]}" ] && echo " (convert to ${OPTIONS[convert_thumbnails]})" || echo "")" || echo "Don't embed")"
    echo -e "${BLUE}Metadata:${NC} $([ "${OPTIONS[embed_metadata]}" == "yes" ] && echo "Embed metadata" || echo "No metadata")$([ "${OPTIONS[embed_chapters]}" == "yes" ] && echo " + chapters" || echo "")$([ "${OPTIONS[embed_info_json]}" == "yes" ] && echo " + info.json" || echo "")"
    echo -e "${BLUE}Subtitles:${NC} $([ "${OPTIONS[subtitles]}" == "yes" ] && echo "Yes$([ "${OPTIONS[write_subs]}" == "yes" ] && echo " (download)" || echo "")$([ "${OPTIONS[embed_subs]}" == "yes" ] && echo " (embed)" || echo "")$([ -n "${OPTIONS[subtitles_lang]}" ] && echo " - Language: ${OPTIONS[subtitles_lang]}" || echo "")" || echo "No")"
    echo -e "${BLUE}Audio extraction:${NC} $([ "${OPTIONS[extract_audio]}" == "yes" ] && echo "Yes - Format: ${OPTIONS[audio_format]}, Quality: ${OPTIONS[audio_quality]}" || echo "No")"
    echo -e "${BLUE}Video remux:${NC} $([ -n "${OPTIONS[remux_video]}" ] && echo "Yes - Container: ${OPTIONS[remux_video]}" || echo "No")"
    echo -e "${BLUE}Output template:${NC} ${OPTIONS[output_template]}"
    echo -e "${BLUE}Verbose mode:${NC} ${OPTIONS[verbose]}"
    echo -e "${BLUE}Restrict filenames:${NC} ${OPTIONS[restrict_filenames]}"
    echo -e "${BLUE}Preserve upload date:${NC} ${OPTIONS[no_mtime]}"
    echo -e "${BLUE}Concurrent fragments:${NC} ${OPTIONS[concurrent_fragments]}"
    echo -e "${BLUE}Delay between requests:${NC} ${OPTIONS[sleep_requests]}s"
    echo ""
    read -rp "Press Enter to continue..."
}

show_main_menu() {
    while true; do
        echo ""
        echo -e "${GREEN}=== Main Menu ==="
        echo -e "${NC}1) Configure subtitles"
        echo "2) Configure thumbnail"
        echo "3) Configure metadata and chapters"
        echo "4) Configure format and quality"
        echo "5) Configure audio extraction and conversion"
        echo "6) Configure output filename"
        echo "7) Advanced options"
        echo "8) View current configuration"
        echo "9) Check for updates"
        echo "10) Start download"
        echo "11) Cancel"
        echo ""
        read -rp "Select an option [1-9]: " main_choice
        
        case $main_choice in
            1) show_subtitles_menu ;;
            2) show_thumbnail_menu ;;
            3) show_metadata_menu ;;
            4) show_format_menu ;;
            5) show_audio_menu ;;
            6) show_output_menu ;;
            7) show_advanced_menu ;;
            8) show_current_config ;;
            9)
                echo ""
                echo -e "${YELLOW}[UPDATE] Checking components via setup.sh...${NC}"
                if bash "$BASEDIR/setup.sh"; then
                    echo ""
                    echo -e "${GREEN}[INFO] Update check complete. Press Enter to continue...${NC}"
                    read -r
                else
                    echo ""
                    echo -e "${RED}[ERROR] Update failed. Check connection.${NC}"
                    read -r
                fi
                ;;
            10) break ;;
            11) echo -e "${YELLOW}Download cancelled by user.${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option. Please select [1-9]${NC}" ;;
        esac
    done
}

# ==============================================================================
# EXECUTION FUNCTIONS
# ==============================================================================

# Build and execute yt-dlp command
execute_ytdlp() {
    local cmd=("$BINDIR/yt-dlp")
    
    # Base options
    if [ "${OPTIONS[verbose]}" == "yes" ]; then
        cmd+=(--verbose)
    fi
    
    cmd+=(--socket-timeout 30)
    cmd+=(--retries 10)
    cmd+=(--fragment-retries 10)

    # User-Agent and Referer are handled automatically by yt-dlp for better stability
    cmd+=(--sleep-requests "${OPTIONS[sleep_requests]}")
    cmd+=(--js-runtimes "deno:${BINDIR}/deno")
    cmd+=(--ffmpeg-location "${BINDIR}/ffmpeg")
    cmd+=(--concurrent-fragments "${OPTIONS[concurrent_fragments]}")
    cmd+=(-f "${OPTIONS[format]}")
    
    # Thumbnail options
    if [ "${OPTIONS[embed_thumbnail]}" == "yes" ]; then
        cmd+=(--embed-thumbnail)
        if [ -n "${OPTIONS[convert_thumbnails]}" ]; then
            cmd+=(--convert-thumbnails "${OPTIONS[convert_thumbnails]}")
        fi
    fi
    
    if [ -n "${OPTIONS[merge_output_format]}" ]; then
        cmd+=(--merge-output-format "${OPTIONS[merge_output_format]}")
    fi

    # Metadata options
    if [ "${OPTIONS[embed_metadata]}" == "yes" ]; then
        cmd+=(--embed-metadata)
    fi
    
    if [ "${OPTIONS[embed_chapters]}" == "yes" ]; then
        cmd+=(--embed-chapters)
    fi
    
    if [ "${OPTIONS[embed_info_json]}" == "yes" ]; then
        cmd+=(--embed-info-json)
    fi

    # Subtitle options
    if [ "${OPTIONS[subtitles]}" == "yes" ]; then
        local sub_lang="${OPTIONS[subtitles_lang]}"
        [[ -z "$sub_lang" || "$sub_lang" == "all" ]] && sub_lang="all"

        # If embed is enabled, it automatically downloads first
        if [ "${OPTIONS[embed_subs]}" == "yes" ]; then
            cmd+=(--embed-subs --sub-langs "$sub_lang")
        elif [ "${OPTIONS[write_subs]}" == "yes" ]; then
            cmd+=(--write-subs --sub-langs "$sub_lang")
        fi
    fi

    # Audio extraction options
    if [ "${OPTIONS[extract_audio]}" == "yes" ]; then
        cmd+=(--extract-audio)
        if [ -n "${OPTIONS[audio_format]}" ]; then
            cmd+=(--audio-format "${OPTIONS[audio_format]}")
        fi
        if [ -n "${OPTIONS[audio_quality]}" ]; then
            cmd+=(--audio-quality "${OPTIONS[audio_quality]}")
        fi
    fi
    
    # Video remux options
    if [ -n "${OPTIONS[remux_video]}" ]; then
        cmd+=(--remux-video "${OPTIONS[remux_video]}")
    fi
    
    # Output options
    if [ "${OPTIONS[restrict_filenames]}" == "yes" ]; then
        cmd+=(--restrict-filenames)
    fi
    
    cmd+=(--output "${OPTIONS[output_template]}")
    
    if [ "${OPTIONS[no_mtime]}" == "yes" ]; then
        cmd+=(--no-mtime)
    fi
    
    # Add URL arguments
    cmd+=("${URL_ARGS[@]}")

    "${cmd[@]}"
}

# ==============================================================================
# MAIN EXECUTION FLOW
# ==============================================================================

main() {
    # Parse arguments
    local QUICK_MODE=false
    URL_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick|-q)
                QUICK_MODE=true
                shift
                ;;
            --help|-h)
                echo "Usage: ./download.sh [OPTIONS] [URL]"
                echo ""
                echo "Options:"
                echo "  -q, --quick    Use quick mode (default settings, no menu)"
                echo "  -h, --help     Show this help message"
                echo ""
                echo "If no options are provided, an interactive menu will be shown."
                exit 0
                ;;
            *)
                URL_ARGS+=("$1")
                shift
                ;;
        esac
    done

    # Check if URL was provided
    if [ ${#URL_ARGS[@]} -eq 0 ]; then
        echo -e "${RED}Error: No URL provided.${NC}"
        echo "Usage: ./download.sh [OPTIONS] [URL]"
        echo "Example: ./download.sh https://www.youtube.com/watch?v=XXXXXX"
        echo "Use --help for more information."
        exit 1
    fi

    # Security check
    check_root

    # Verify all required binaries
    check_binary "yt-dlp"
    check_binary "deno"
    check_binary "ffmpeg"
    check_binary "ffprobe"

    # Initial banner
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}      yt-dlp-portable independent-arg       ${NC}"
    echo -e "${BLUE}               ${VERSION}                   ${NC}"
    echo -e "${BLUE}============================================${NC}"

    echo -e "${GREEN}[INFO] Identity managed by yt-dlp internal handler${NC}"

    # Check available disk space
    check_disk_space

    # Run mode
    if [ "$QUICK_MODE" = true ]; then
        echo -e "${GREEN}[INFO] Quick mode enabled. Using default configuration...${NC}"
    else
        echo -e "${GREEN}[INFO] Interactive mode. Configure your options:${NC}"
        show_main_menu
    fi

    # Execute download
    echo ""
    echo -e "${GREEN}[INFO] Starting download...${NC}"
    echo ""

    # Execute yt-dlp with detailed error handling
    if ! execute_ytdlp; then
        exit_code=$?
        echo ""
        echo -e "${RED}[FAILURE] yt-dlp finished with error code: $exit_code${NC}"
        case $exit_code in
            1)
                echo -e "${YELLOW}Possible causes: Invalid URL, network error, or unsupported format.${NC}"
                ;;
            2)
                echo -e "${YELLOW}Possible causes: Missing dependencies or configuration issue.${NC}"
                ;;
            130)
                echo -e "${YELLOW}Download was interrupted by user (Ctrl+C).${NC}"
                ;;
            *)
                echo -e "${YELLOW}Check the error messages above for details.${NC}"
                ;;
        esac
        echo ""
        echo -e "${BLUE}Need help? Check the documentation or try:${NC}"
        echo "  ./download.sh --help"
        exit $exit_code
    fi

    echo -e "${GREEN}[SUCCESS] Process finished successfully.${NC}"
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

main "$@"
