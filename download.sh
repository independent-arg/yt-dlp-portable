#!/bin/bash

# ==============================================================================
# Script Name: yt-dlp-portable (setup.sh)
# Version:     v0.6.2
# Author:      independent-arg
# License:     MIT
# ==============================================================================

set -euo pipefail

readonly VERSION="v0.6.2"
readonly LAST_UPDATED="2025-01-02"

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
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Verify all required binaries
check_binary "yt-dlp"
check_binary "deno"
check_binary "ffmpeg"
check_binary "ffprobe"

# Parse arguments for quick mode or URL
QUICK_MODE=false
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

# Initial banner
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}      yt-dlp-portable independent-arg       ${NC}"
echo -e "${BLUE}               ${VERSION}                   ${NC}"
echo -e "${BLUE}============================================${NC}"

echo -e "${GREEN}[INFO] Identity managed by yt-dlp internal handler${NC}"

# Check available disk space
check_disk_space

# Default options (quick mode)
declare -A OPTIONS
OPTIONS[format]="bestvideo*+bestaudio/best"
OPTIONS[embed_thumbnail]="yes"
OPTIONS[convert_thumbnails]="jpg"
OPTIONS[merge_output_format]="mkv"
OPTIONS[subtitles]="no"
OPTIONS[subtitles_lang]=""
OPTIONS[embed_subs]="no"
OPTIONS[write_subs]="no"
OPTIONS[output_template]="%(title)s [%(id)s].%(ext)s"
OPTIONS[verbose]="yes"
OPTIONS[restrict_filenames]="yes"
OPTIONS[no_mtime]="yes"
OPTIONS[concurrent_fragments]="5"
OPTIONS[sleep_requests]="1.5"

# Interactive menu functions
show_subtitles_menu() {
    echo ""
    echo -e "${YELLOW}=== Subtitles ==="
    echo -e "${NC}1) Don't download subtitles (default)"
    echo "2) Download subtitles (separate file)"
    echo "3) Embed subtitles in video"
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
    echo -e "${YELLOW}=== Thumbnail ==="
    echo -e "${NC}1) Embed and convert to JPG (recommended, default)"
    echo "2) Embed thumbnail (original format)"
    echo "3) Embed and convert to PNG"
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

show_format_menu() {
    echo ""
    echo -e "${YELLOW}=== Format and Quality ==="
    echo -e "${NC}1) Highest quality available (recommended, default)"
    echo "   Downloads and merges best video with best audio"
    echo "2) Quick download mode (faster, good quality)"
    echo "   Single pre-merged file, but often lower quality than option 1"
    echo "3) Video only (no sound)"
    echo "4) Audio only (no video)"
    echo "5) Choose specific resolution (4K, 1080p, 720p, etc.)"
    echo "6) Custom format (advanced)"
    echo "7) Back to main menu"
    echo ""
    read -rp "Select an option [1-7]: " format_choice

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
        7)
            return
            ;;
        *)
            echo -e "${RED}Invalid option${NC}"
            ;;
    esac
}

show_output_menu() {
    echo ""
    echo -e "${YELLOW}=== Filename Template ==="
    echo -e "${NC}1) Title [ID].ext (default)"
    echo "2) Title.ext"
    echo "3) ID.ext"
    echo "4) Title - Channel [ID].ext"
    echo "5) Custom"
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
    echo "2) Restrict filenames: $([ "${OPTIONS[restrict_filenames]}" == "yes" ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
    echo "3) Don't modify file date: $([ "${OPTIONS[no_mtime]}" == "yes" ] && echo -e "${GREEN}Yes${NC}" || echo -e "${RED}No${NC}")"
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

show_main_menu() {
    while true; do
        echo ""
        echo -e "${GREEN}=== Configuration Menu ==="
        echo -e "${NC}1) Configure subtitles"
        echo "2) Configure thumbnail"
        echo "3) Configure format and quality"
        echo "4) Configure filename"
        echo "5) Advanced options"
        echo "6) View current configuration"
        echo "7) Start download"
        echo "8) Cancel"
        echo ""
        read -rp "Select an option [1-8]: " main_choice

        case $main_choice in
            1)
                show_subtitles_menu
                ;;
            2)
                show_thumbnail_menu
                ;;
            3)
                show_format_menu
                ;;
            4)
                show_output_menu
                ;;
            5)
                show_advanced_menu
                ;;
            6)
                show_current_config
                ;;
            7)
                break
                ;;
            8)
                echo -e "${YELLOW}Download cancelled by user.${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option Please select [1-8]${NC}"
                ;;
        esac
    done
}

show_current_config() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║      Current configuration summary       ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Format:${NC} ${OPTIONS[format]}"
    echo -e "${BLUE}Thumbnail:${NC} $([ "${OPTIONS[embed_thumbnail]}" == "yes" ] && echo "Embed$([ -n "${OPTIONS[convert_thumbnails]}" ] && echo " (convert to ${OPTIONS[convert_thumbnails]})" || echo "")" || echo "Don't embed")"
    echo -e "${BLUE}Subtitles:${NC} $([ "${OPTIONS[subtitles]}" == "yes" ] && echo "Yes$([ "${OPTIONS[write_subs]}" == "yes" ] && echo " (download)" || echo "")$([ "${OPTIONS[embed_subs]}" == "yes" ] && echo " (embed)" || echo "")$([ -n "${OPTIONS[subtitles_lang]}" ] && echo " - Language: ${OPTIONS[subtitles_lang]}" || echo "")" || echo "No")"
    echo -e "${BLUE}Output template:${NC} ${OPTIONS[output_template]}"
    echo -e "${BLUE}Verbose mode:${NC} ${OPTIONS[verbose]}"
    echo -e "${BLUE}Restrict filenames:${NC} ${OPTIONS[restrict_filenames]}"
    echo -e "${BLUE}Don't modify date:${NC} ${OPTIONS[no_mtime]}"
    echo -e "${BLUE}Concurrent fragments:${NC} ${OPTIONS[concurrent_fragments]}"
    echo -e "${BLUE}Sleep time:${NC} ${OPTIONS[sleep_requests]}s"
    echo ""
    read -rp "Press Enter to continue..."
}

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

# Main execution
if [ "$QUICK_MODE" = true ]; then
    echo -e "${GREEN}[INFO] Quick mode enabled. Using default configuration...${NC}"
else
    echo -e "${GREEN}[INFO] Interactive mode. Configure your options:${NC}"
    show_main_menu
fi

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
