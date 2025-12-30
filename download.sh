#!/bin/bash

# ==============================================================================
# Script Name: yt-dlp-portable (download.sh)
# Version:     v0.6.0-beta1
# Author:      independent-arg
# License:     MIT
# ==============================================================================

set -euo pipefail

readonly VERSION="v0.6.0-beta1"
readonly LAST_UPDATED="2025-12-30"

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

# Basic URL validation function
validate_url() {
    local url="$1"
    # Basic check: URL should start with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    # Check for common video platform patterns
    if [[ "$url" =~ (youtube\.com|youtu\.be|vimeo\.com|dailymotion\.com|twitch\.tv) ]]; then
        return 0
    fi
    # Allow other URLs (yt-dlp supports many platforms)
    return 0
}

# Validate URLs
for url in "${URL_ARGS[@]}"; do
    if ! validate_url "$url"; then
        echo -e "${YELLOW}[WARN] URL may be invalid: $url${NC}"
        echo -e "${YELLOW}Continuing anyway (yt-dlp will validate)...${NC}"
    fi
done

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

RANDOM_USER_AGENT=$(generate_random_user_agent)

# Initial banner
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}      yt-dlp-portable independent-arg       ${NC}"
echo -e "${GREEN}============================================${NC}"

echo -e "${GREEN}[STEALTH] Identity assigned: $RANDOM_USER_AGENT${NC}"

# Default options (quick mode)
declare -A OPTIONS
OPTIONS[format]="bestvideo+bestaudio/best"
OPTIONS[embed_thumbnail]="yes"
OPTIONS[convert_thumbnails]="jpg"
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
            ;;
        2)
            OPTIONS[embed_thumbnail]="yes"
            OPTIONS[convert_thumbnails]=""
            ;;
        3)
            OPTIONS[embed_thumbnail]="yes"
            OPTIONS[convert_thumbnails]="png"
            ;;
        4)
            OPTIONS[embed_thumbnail]="no"
            OPTIONS[convert_thumbnails]=""
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
            OPTIONS[format]="bestvideo+bestaudio/best"
            ;;
        2)
            OPTIONS[format]="best"
            ;;
        3)
            OPTIONS[format]="bestvideo"
            ;;
        4)
            OPTIONS[format]="bestaudio"
            ;;
        5)
            echo ""
            echo "Options: 2160p, 1440p, 1080p, 720p, 480p, 360p, 240p, 144p"
            read -rp "Select quality (e.g., 1080p): " quality
            # Sanitize input: remove any non-alphanumeric characters except 'p'
            quality=$(echo "$quality" | tr -cd '0-9p')
            if [[ -n "$quality" && "$quality" =~ ^[0-9]+p?$ ]]; then
                # Remove 'p' if present for height calculation
                height_num=$(echo "$quality" | tr -d 'p')
                OPTIONS[format]="bestvideo[height<=${height_num}]+bestaudio/best[height<=${height_num}]"
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
                custom_format=$(echo "$custom_format" | tr -d '\n\r\t')
                OPTIONS[format]="$custom_format"
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
            ;;
        2)
            OPTIONS[output_template]="%(title)s.%(ext)s"
            ;;
        3)
            OPTIONS[output_template]="%(id)s.%(ext)s"
            ;;
        4)
            OPTIONS[output_template]="%(title)s - %(uploader)s [%(id)s].%(ext)s"
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
            else
                OPTIONS[verbose]="yes"
            fi
            show_advanced_menu
            ;;
        2)
            if [ "${OPTIONS[restrict_filenames]}" == "yes" ]; then
                OPTIONS[restrict_filenames]="no"
            else
                OPTIONS[restrict_filenames]="yes"
            fi
            show_advanced_menu
            ;;
        3)
            if [ "${OPTIONS[no_mtime]}" == "yes" ]; then
                OPTIONS[no_mtime]="no"
            else
                OPTIONS[no_mtime]="yes"
            fi
            show_advanced_menu
            ;;
        4)
            echo ""
            read -rp "Number of concurrent fragments [1-10]: " fragments
            # Sanitize: only digits
            fragments=$(echo "$fragments" | tr -cd '0-9')
            if [[ -n "$fragments" && "$fragments" =~ ^[0-9]+$ ]] && [ "$fragments" -ge 1 ] && [ "$fragments" -le 10 ]; then
                OPTIONS[concurrent_fragments]="$fragments"
            else
                echo -e "${RED}Invalid value. Must be a number between 1 and 10.${NC}"
                echo -e "${YELLOW}Keeping current value: ${OPTIONS[concurrent_fragments]}${NC}"
            fi
            show_advanced_menu
            ;;
        5)
            echo ""
            read -rp "Sleep time in seconds (e.g., 1.5): " sleep_time
            # Sanitize: allow digits and one decimal point
            sleep_time=$(echo "$sleep_time" | tr -cd '0-9.')
            # Validate format: number with optional decimal, must be positive
            if [[ -n "$sleep_time" && "$sleep_time" =~ ^[0-9]+\.?[0-9]*$ ]]; then
                # Check if it's greater than 0 (basic check: not just "0" or "0.0")
                if [[ "$sleep_time" != "0" && "$sleep_time" != "0.0" && "$sleep_time" != "0." ]]; then
                    OPTIONS[sleep_requests]="$sleep_time"
                else
                    echo -e "${RED}Invalid value. Must be greater than 0.${NC}"
                    echo -e "${YELLOW}Keeping current value: ${OPTIONS[sleep_requests]}s${NC}"
                fi
            else
                echo -e "${RED}Invalid value. Must be a positive number.${NC}"
                echo -e "${YELLOW}Keeping current value: ${OPTIONS[sleep_requests]}s${NC}"
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
                echo -e "${YELLOW}Download cancelled.${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

show_current_config() {
    echo ""
    echo -e "${GREEN}=== Current Configuration ==="
    echo -e "${NC}Format: ${OPTIONS[format]}"
    echo "Thumbnail: $([ "${OPTIONS[embed_thumbnail]}" == "yes" ] && echo "Embed$([ -n "${OPTIONS[convert_thumbnails]}" ] && echo " (convert to ${OPTIONS[convert_thumbnails]})" || echo "")" || echo "Don't embed")"
    echo "Subtitles: $([ "${OPTIONS[subtitles]}" == "yes" ] && echo "Yes$([ "${OPTIONS[write_subs]}" == "yes" ] && echo " (download)" || echo "")$([ "${OPTIONS[embed_subs]}" == "yes" ] && echo " (embed)" || echo "")$([ -n "${OPTIONS[subtitles_lang]}" ] && echo " - Language: ${OPTIONS[subtitles_lang]}" || echo "")" || echo "No")"
    echo "Output template: ${OPTIONS[output_template]}"
    echo "Verbose mode: ${OPTIONS[verbose]}"
    echo "Restrict filenames: ${OPTIONS[restrict_filenames]}"
    echo "Don't modify date: ${OPTIONS[no_mtime]}"
    echo "Concurrent fragments: ${OPTIONS[concurrent_fragments]}"
    echo "Sleep time: ${OPTIONS[sleep_requests]}s"
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
    
    cmd+=(--user-agent "$RANDOM_USER_AGENT")
    cmd+=(--referer "https://www.youtube.com/")
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
    
    # Subtitle options
    if [ "${OPTIONS[subtitles]}" == "yes" ]; then
        if [ "${OPTIONS[write_subs]}" == "yes" ]; then
            if [ -n "${OPTIONS[subtitles_lang]}" ] && [ "${OPTIONS[subtitles_lang]}" != "all" ]; then
                cmd+=(--write-subs --sub-langs "${OPTIONS[subtitles_lang]}")
            else
                cmd+=(--write-subs --sub-langs all)
            fi
        fi
        if [ "${OPTIONS[embed_subs]}" == "yes" ]; then
            if [ -n "${OPTIONS[subtitles_lang]}" ] && [ "${OPTIONS[subtitles_lang]}" != "all" ]; then
                cmd+=(--embed-subs --sub-langs "${OPTIONS[subtitles_lang]}")
            else
                cmd+=(--embed-subs --sub-langs all)
            fi
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
    
    # Execute the command directly
    if ! "${cmd[@]}"; then
        return $?
    fi
    return 0
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

# Execute yt-dlp
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
    exit $exit_code
fi

echo -e "${GREEN}[SUCCESS] Process finished successfully.${NC}"
