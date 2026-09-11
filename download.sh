#!/bin/bash

# ==============================================================================
# Script Name: yt-dlp-portable (download.sh)
# Author:      independent-arg
# License:     MIT
# ==============================================================================

set -euo pipefail
shopt -s inherit_errexit

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib.sh
source "${LIB_DIR}/lib.sh"

# ==============================================================================
# CONSTANTS & GLOBAL STATE
# ==============================================================================

readonly CONFIG_FILE=".yt-dlp-portable.config"
readonly BINDIR="bin"

# Config (last-used OUTPUT_DIR) and the download-archive file are intentionally
# resolved relative to the CURRENT directory, not this script's location. cd
# into whatever folder you're organizing downloads in and each folder keeps
# its own remembered output dir and dedup history. Binaries, by contrast, are
# always resolved relative to the script's own real path (see get_bin_dir),
# so this still works if download.sh is invoked via an absolute path or a
# symlink from elsewhere.
declare -A OPTIONS
declare -a URL_LIST=()
OUTPUT_DIR=""
QUICK_MODE=false

trap 'printf "\n%b[INFO] Script interrupted by user.%b\n" "${YELLOW}" "${NC}"; exit 130' INT

# ==============================================================================
# CONFIGURATION MANAGEMENT
# ==============================================================================

load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # Manually parse configuration to avoid arbitrary code execution via
        # source. We only look for OUTPUT_DIR since it's the only persisted key.
        local config_line
        config_line=$(grep "^OUTPUT_DIR=" "$CONFIG_FILE" | head -n 1) || :

        if [[ -n "$config_line" ]]; then
            local val="${config_line#OUTPUT_DIR=}"
            val="${val%\"}"
            val="${val#\"}"
            OUTPUT_DIR="${val//\\\"/\"}"
        fi
    fi
}

save_config() {
    local safe_dir="${OUTPUT_DIR//\"/\\\"}"
    if ! printf "OUTPUT_DIR=\"%s\"\n" "$safe_dir" > "$CONFIG_FILE"; then
        _error "Failed to save configuration to $CONFIG_FILE"
        return 1
    fi
}

# ==============================================================================
# SYSTEM UTILITIES
# ==============================================================================

get_script_dir() {
    dirname "$(resolve_script_path)"
}

get_bin_dir() {
    printf '%s/%s' "$(get_script_dir)" "$BINDIR"
}

refresh_screen() {
    clear
    show_banner
}

# ==============================================================================
# DEFAULTS
# ==============================================================================

init_defaults() {
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
    # "no" matches yt-dlp's own default (--no-mtime) so nothing extra needs to
    # be passed on the common path; "yes" is the one case that needs an
    # explicit --mtime (see execute_ytdlp).
    OPTIONS[preserve_mtime]="no"
    OPTIONS[concurrent_fragments]="5"
    OPTIONS[sleep_requests]="1.5"
    OPTIONS[playlist_handling]="auto"
    OPTIONS[playlist_items]=""
    OPTIONS[playlist_reverse]="no"
    OPTIONS[use_playlist_template]="no"
    OPTIONS[use_archive]="no"
    OPTIONS[archive_file]="download_archive.txt"
    OPTIONS[break_on_existing]="no"
    OPTIONS[max_downloads]=""
    OPTIONS[ignore_errors]="no"
    OPTIONS[max_res_sort]=""
    OPTIONS[live_from_start]="no"
    OPTIONS[wait_for_video]=""
}

# ==============================================================================
# SYSTEM CHECKS
# ==============================================================================

check_system() {
    require_non_root

    local path_to_bin bin current_file
    path_to_bin=$(get_bin_dir)

    for bin in "yt-dlp" "ffmpeg" "ffprobe" "deno"; do
        current_file="$path_to_bin/$bin"
        if [[ ! -f "$current_file" ]]; then
            _error "Binary not found: $bin"
            _error "Please run: bash setup.sh"
            exit 1
        fi
        if [[ ! -x "$current_file" ]]; then
            _warn "Fixing execution permissions for $bin..."
            chmod +x "$current_file"
        fi
    done

    # Check space where the files will actually land, not necessarily the
    # current directory. Walk up to the nearest existing ancestor since
    # OUTPUT_DIR may not have been created yet.
    local target_dir="${OUTPUT_DIR:-.}"
    while [[ ! -d "$target_dir" ]]; do
        target_dir="$(dirname "$target_dir")"
    done

    local available_kb available_mb
    available_kb=$(df -Pk "$target_dir" | awk 'NR==2 {print $4}')
    available_mb=$((available_kb / 1024))

    if [[ "$available_kb" -lt 1048576 ]]; then
        _warn "Low disk space: ${available_mb}MB available in ${target_dir}"
        printf "%bLarge downloads may fail. Consider freeing up space.%b\n" "${YELLOW}" "${NC}"

        if [[ "$QUICK_MODE" == "true" ]]; then
            # --quick is documented for cron/unattended use, so it must never
            # block on a prompt (an unattended `read` would either hang or
            # read EOF as "no" and silently exit 0 without downloading).
            _warn "Continuing anyway (--quick never blocks on a prompt)."
        else
            local reply=""
            read -rp "Continue anyway? (y/N): " -n 1 reply
            printf "\n"
            if [[ "${reply,,}" != "y" ]]; then
                printf "%bDownload cancelled by user.%b\n" "${YELLOW}" "${NC}"
                exit 0
            fi
        fi
    fi
}

# ==============================================================================
# MENUS
# ==============================================================================

manage_urls() {
    local choice="" new_url="" i
    while true; do
        refresh_screen
        printf "%b=== URL Manager ===%b\n\n" "${YELLOW}" "${NC}"
        if [ ${#URL_LIST[@]} -eq 0 ]; then
            printf "(List is empty)\n"
        else
            for i in "${!URL_LIST[@]}"; do
                printf "%d. %s\n" "$((i+1))" "${URL_LIST[$i]}"
            done
        fi
        printf "\n1) Add URL\n2) Clear list\n3) Back\n\n"
        read -rp "Select an option [1-3]: " choice
        case "$choice" in
            1)  read -rp "Enter URL: " new_url
                if [[ "$new_url" =~ ^https?:// ]]; then
                    URL_LIST+=("$new_url")
                    printf "\n%bURL added.%b\n" "${GREEN}" "${NC}"; sleep 1
                else
                    printf "\n%b[ERROR] Invalid URL.%b\n" "${RED}" "${NC}"; sleep 2
                fi ;;
            2)  URL_LIST=(); printf "%bList cleared.%b\n" "${GREEN}" "${NC}"; sleep 1 ;;
            3)  return ;;
            *)  printf "%bInvalid option.%b\n" "${RED}" "${NC}"; sleep 1 ;;
        esac
    done
}

manage_output_dir() {
    local choice="" new_dir="" reply=""
    while true; do
        refresh_screen
        printf "%b=== Output Directory ===%b\n\n" "${YELLOW}" "${NC}"
        printf "Current: %s\n\n" "${OUTPUT_DIR:-$(pwd)}"
        printf "1) Change directory\n2) Reset to default\n3) Back\n\n"
        read -rp "Select an option [1-3]: " choice
        case "$choice" in
            1)  read -rp "Absolute path: " new_dir
                if [[ -n "$new_dir" ]]; then
                    if [[ "$new_dir" != /* ]]; then
                        printf "\n%b[WARN] Path does not appear to be absolute. Using relative path.%b\n" "${YELLOW}" "${NC}"
                    fi
                    if [[ ! -d "$new_dir" ]]; then
                        read -rp "Directory does not exist. Create it? (y/N): " -n 1 reply
                        printf "\n"
                        if [[ "${reply,,}" == "y" ]] && mkdir -p "$new_dir"; then
                            printf "%bDirectory created.%b\n" "${GREEN}" "${NC}"
                            OUTPUT_DIR="$new_dir"
                            save_config || _warn "Directory set for this session, but could not save it to $CONFIG_FILE"
                        fi
                    else
                        OUTPUT_DIR="$new_dir"
                        if save_config; then
                            printf "%bDirectory set.%b\n" "${GREEN}" "${NC}"
                        else
                            _warn "Directory set for this session, but could not save it to $CONFIG_FILE"
                        fi
                    fi
                fi; sleep 1 ;;
            2)  OUTPUT_DIR=""
                if save_config; then
                    printf "%bDirectory reset to default.%b\n" "${GREEN}" "${NC}"
                else
                    _warn "Could not save this to $CONFIG_FILE"
                fi
                sleep 1 ;;
            3)  return ;;
            *)  printf "%bInvalid option.%b\n" "${RED}" "${NC}"; sleep 1 ;;
        esac
    done
}

configure_post_processing() {
    local choice="" sub_lang=""

    while true; do
        refresh_screen
        printf "%b=== Configure Post-Processing ===%b\n\n" "${YELLOW}" "${NC}"
        printf "1) Subtitles:         [%s] (Lang: %s)\n" "${OPTIONS[subtitles]}" "${OPTIONS[subtitles_lang]:-all}"
        printf "2) Embed Thumbnail:   [%s] (Format: %s)\n" "${OPTIONS[embed_thumbnail]}" "${OPTIONS[convert_thumbnails]:-original}"
        printf "3) Embed Metadata:    [%s] (Chapters: %s)\n" "${OPTIONS[embed_metadata]}" "${OPTIONS[embed_chapters]}"
        printf "4) Back\n\n"

        read -rp "Select an option [1-4]: " choice
        printf "\n"

        case "$choice" in
            1)
                printf "1) Don't download (default)\n2) Download (.srt file)\n3) Embed in video\n4) Download and embed\n\n"
                read -rp "Select sub-option [1-4]: " choice
                case "$choice" in
                    1)
                        OPTIONS[subtitles]="no"; OPTIONS[write_subs]="no"
                        OPTIONS[embed_subs]="no"; OPTIONS[subtitles_lang]=""
                        printf "\n%bSubtitles disabled.%b\n" "${GREEN}" "${NC}" ;;
                    2|3|4)
                        read -rp "Language (e.g., en, es, all) [Enter for all]: " sub_lang
                        OPTIONS[subtitles]="yes"
                        OPTIONS[subtitles_lang]=$(tr -cd 'a-zA-Z0-9+,-' <<< "${sub_lang:-all}")
                        OPTIONS[write_subs]=$([[ "$choice" == "2" || "$choice" == "4" ]] && echo "yes" || echo "no")
                        OPTIONS[embed_subs]=$([[ "$choice" == "3" || "$choice" == "4" ]] && echo "yes" || echo "no")
                        printf "\n%bSubtitles configured.%b\n" "${GREEN}" "${NC}" ;;
                    *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}" ;;
                esac; sleep 1 ;;
            2)
                printf "1) Embed as JPG (Recommended, forces MKV)\n2) Embed original\n3) Embed as PNG\n4) Don't embed\n\n"
                read -rp "Select sub-option [1-4]: " choice
                case "$choice" in
                    1) OPTIONS[embed_thumbnail]="yes"; OPTIONS[convert_thumbnails]="jpg"; OPTIONS[merge_output_format]="mkv" ;;
                    2) OPTIONS[embed_thumbnail]="yes"; OPTIONS[convert_thumbnails]=""; OPTIONS[merge_output_format]="" ;;
                    3) OPTIONS[embed_thumbnail]="yes"; OPTIONS[convert_thumbnails]="png"; OPTIONS[merge_output_format]="" ;;
                    4) OPTIONS[embed_thumbnail]="no"; OPTIONS[convert_thumbnails]=""; OPTIONS[merge_output_format]="" ;;
                    *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}"; sleep 1; continue ;;
                esac
                printf "\n%bThumbnail settings updated.%b\n" "${GREEN}" "${NC}"; sleep 1 ;;
            3)
                printf "1) Don't embed (default)\n2) Basic (title, artist, date)\n3) Basic + Chapters\n4) All (includes info.json)\n\n"
                read -rp "Select sub-option [1-4]: " choice
                case "$choice" in
                    1) OPTIONS[embed_metadata]="no"; OPTIONS[embed_chapters]="no"; OPTIONS[embed_info_json]="no" ;;
                    2) OPTIONS[embed_metadata]="yes"; OPTIONS[embed_chapters]="no"; OPTIONS[embed_info_json]="no" ;;
                    3) OPTIONS[embed_metadata]="yes"; OPTIONS[embed_chapters]="yes"; OPTIONS[embed_info_json]="no" ;;
                    4) OPTIONS[embed_metadata]="yes"; OPTIONS[embed_chapters]="yes"; OPTIONS[embed_info_json]="yes" ;;
                    *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}"; sleep 1; continue ;;
                esac
                printf "\n%bMetadata settings updated.%b\n" "${GREEN}" "${NC}"; sleep 1 ;;
            4) return ;;
            *) printf "%bInvalid option.%b\n" "${RED}" "${NC}"; sleep 1 ;;
        esac
    done
}

configure_format_and_audio() {
    local choice="" qual="" h="" remux="" cfmt="" fmt=""

    while true; do
        refresh_screen
        printf "%b=== Configure Format & Audio ===%b\n\n" "${YELLOW}" "${NC}"
        if [[ -n "${OPTIONS[max_res_sort]:-}" ]]; then
            printf "1) Video Format base:   [%s] (Sort Capped: %sp)\n" "${OPTIONS[format]}" "${OPTIONS[max_res_sort]}"
        else
            printf "1) Video Format base:   [%s]\n" "${OPTIONS[format]}"
        fi
        printf "2) Remux Container:     [%s]\n" "${OPTIONS[remux_video]:-none}"
        printf "3) Audio Extraction:    [%s] (Format: %s, Qual: %s)\n" "${OPTIONS[extract_audio]}" "${OPTIONS[audio_format]:-none}" "${OPTIONS[audio_quality]:-none}"
        printf "4) Back\n\n"

        read -rp "Select an option [1-4]: " choice
        printf "\n"

        case "$choice" in
            1)
                printf "1) Best quality (Video+Audio)\n2) Best pre-merged (Faster)\n3) Video only\n4) Audio only (no convert)\n5) Specific resolution\n6) Custom format string\n\n"
                read -rp "Select sub-option [1-6]: " choice
                case "$choice" in
                    1) OPTIONS[format]="bestvideo*+bestaudio/best"; OPTIONS[remux_video]=""; OPTIONS[max_res_sort]="" ;;
                    2) OPTIONS[format]="best"; OPTIONS[remux_video]=""; OPTIONS[max_res_sort]="" ;;
                    3) OPTIONS[format]="bestvideo"; OPTIONS[remux_video]=""; OPTIONS[max_res_sort]="" ;;
                    4) OPTIONS[format]="bestaudio"; OPTIONS[remux_video]=""; OPTIONS[max_res_sort]="" ;;
                    5)
                       read -rp "Select max resolution (e.g., 1080): " qual
                       h=$(tr -cd '0-9' <<< "$qual")
                       if [[ -n "$h" ]]; then
                           OPTIONS[format]="bestvideo*+bestaudio/best"
                           OPTIONS[max_res_sort]="$h"
                           OPTIONS[remux_video]=""
                       fi ;;
                    6) read -rp "Format (see yt-dlp docs): " cfmt
                       if [[ -n "$cfmt" ]]; then
                           # Only strip control chars (e.g. escape sequences); the value is passed as a
                           # literal argv to yt-dlp (never through a shell), so selector syntax like
                           # commas, spaces, '*', '.', '!' etc. must be preserved
                           OPTIONS[format]=$(tr -d '[:cntrl:]' <<< "$cfmt")
                           OPTIONS[remux_video]=""; OPTIONS[max_res_sort]=""
                       fi ;;
                    *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}"; sleep 1; continue ;;
                esac
                printf "\n%bFormat configuration updated.%b\n" "${GREEN}" "${NC}"; sleep 1 ;;
            2)
                read -rp "Target container (mp4, mkv, etc): " remux
                remux=$(tr -cd 'a-z0-9' <<< "$remux")
                if [[ -n "$remux" ]]; then
                    if [[ "${OPTIONS[extract_audio]}" == "yes" ]]; then
                        printf "%b[INFO] Disabling audio extraction: remuxing applies to the video container.%b\n" "${CYAN}" "${NC}"
                        OPTIONS[extract_audio]="no"; OPTIONS[audio_format]=""; OPTIONS[audio_quality]=""
                        OPTIONS[format]="bestvideo*+bestaudio/best"
                    fi
                    OPTIONS[remux_video]="$remux"
                    printf "\n%bRemux set to: %s%b\n" "${GREEN}" "$remux" "${NC}"
                else
                    printf "\n%b[ERROR] Invalid container format.%b\n" "${RED}" "${NC}"
                fi; sleep 1 ;;
            3)
                printf "1) Disable extraction\n2) MP3\n3) AAC\n4) OPUS\n5) FLAC\n6) M4A\n7) WAV\n8) ALAC\n9) VORBIS\n\n"
                read -rp "Select sub-option [1-9]: " choice
                if [[ "$choice" == "1" ]]; then
                    OPTIONS[extract_audio]="no"; OPTIONS[audio_format]=""; OPTIONS[audio_quality]=""
                    # Restore a video+audio format if it was auto-switched to audio-only
                    if [[ "${OPTIONS[format]}" == "bestaudio/best" || "${OPTIONS[format]}" == "bestaudio" ]]; then
                        OPTIONS[format]="bestvideo*+bestaudio/best"
                        printf "\n%b[INFO] Video format reset to the default (best video + best audio).%b\n" "${CYAN}" "${NC}"
                    fi
                    printf "\n%bAudio extraction disabled.%b\n" "${GREEN}" "${NC}"
                else
                    case "$choice" in
                        2) fmt="mp3";; 3) fmt="aac";; 4) fmt="opus";; 5) fmt="flac";;
                        6) fmt="m4a";; 7) fmt="wav";; 8) fmt="alac";; 9) fmt="vorbis";;
                        *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}"; sleep 1; continue ;;
                    esac
                    if [[ -n "${OPTIONS[remux_video]}" ]]; then
                        printf "%b[INFO] Clearing remux container (%s): audio extraction discards the video stream.%b\n" "${CYAN}" "${OPTIONS[remux_video]}" "${NC}"
                    fi
                    OPTIONS[extract_audio]="yes"; OPTIONS[audio_format]="$fmt"
                    # Avoid downloading and discarding a full video stream just to extract audio
                    OPTIONS[format]="bestaudio/best"; OPTIONS[remux_video]=""; OPTIONS[max_res_sort]=""
                    if [[ "$fmt" != "flac" && "$fmt" != "wav" && "$fmt" != "alac" ]]; then
                        read -rp "Quality [0=best, 5=default, 10=worst]: " qual
                        OPTIONS[audio_quality]=$(tr -cd '0-9' <<< "${qual:-5}")
                    else OPTIONS[audio_quality]="0"; fi
                    printf "\n%bAudio extraction configured.%b\n" "${GREEN}" "${NC}"
                fi; sleep 1 ;;
            4) return ;;
            *) printf "%bInvalid option.%b\n" "${RED}" "${NC}"; sleep 1 ;;
        esac
    done
}

configure_automation_naming() {
    local choice="" items="" name="" limit=""

    while true; do
        refresh_screen
        printf "%b=== Configure Automation & Naming ===%b\n\n" "${YELLOW}" "${NC}"
        printf "1) Playlist Handling: [%s] (Items: %s, Rev: %s)\n" "${OPTIONS[playlist_handling]}" "${OPTIONS[playlist_items]:-all}" "${OPTIONS[playlist_reverse]}"
        printf "2) History Archive:    [%s] (File: %s, Limit: %s)\n" "${OPTIONS[use_archive]}" "${OPTIONS[archive_file]}" "${OPTIONS[max_downloads]:-none}"
        printf "3) Output Name Naming: [%s]\n" "${OPTIONS[output_template]}"
        printf "4) Back\n\n"

        read -rp "Select an option [1-4]: " choice
        printf "\n"

        case "$choice" in
            1)
                printf "1) Single video (ignore playlist)\n2) Entire playlist\n3) Specific items (e.g. 1-5)\n4) Reverse order\n5) Organize in folders\n\n"
                read -rp "Select sub-option [1-5]: " choice
                case "$choice" in
                    1) OPTIONS[playlist_handling]="no-playlist"; OPTIONS[use_playlist_template]="no"; OPTIONS[playlist_items]=""; OPTIONS[playlist_reverse]="no" ;;
                    2) OPTIONS[playlist_handling]="yes-playlist"; OPTIONS[use_playlist_template]="no"; OPTIONS[playlist_items]=""; OPTIONS[playlist_reverse]="no" ;;
                    3) read -rp "Items (e.g., 1-10, 1,3,5): " items
                       OPTIONS[playlist_handling]="yes-playlist"; OPTIONS[use_playlist_template]="no"
                       OPTIONS[playlist_items]=$(tr -cd '0-9,:-' <<< "$items"); OPTIONS[playlist_reverse]="no" ;;
                    4) OPTIONS[playlist_handling]="yes-playlist"; OPTIONS[use_playlist_template]="no"; OPTIONS[playlist_items]=""; OPTIONS[playlist_reverse]="yes" ;;
                    5) OPTIONS[playlist_handling]="yes-playlist"; OPTIONS[use_playlist_template]="yes"; OPTIONS[playlist_items]=""; OPTIONS[playlist_reverse]="no" ;;
                    *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}"; sleep 1; continue ;;
                esac
                printf "\n%bPlaylist settings updated.%b\n" "${GREEN}" "${NC}"; sleep 1 ;;
            2)
                printf "1) Don't use archive\n2) Use archive (skip downloaded)\n3) Use archive + stop on existing\n4) Set download limit (current: %s)\n5) View history entries\n6) Delete history file\n\n" "${OPTIONS[max_downloads]:-none}"
                read -rp "Select sub-option [1-6]: " choice
                case "$choice" in
                    1) OPTIONS[use_archive]="no"; OPTIONS[break_on_existing]="no" ;;
                    2|3)
                       OPTIONS[use_archive]="yes"
                       OPTIONS[break_on_existing]=$([[ "$choice" == "3" ]] && echo "yes" || echo "no")
                       read -rp "Archive filename [${OPTIONS[archive_file]}]: " name
                       [[ -n "$name" ]] && OPTIONS[archive_file]="$name" ;;
                    4) read -rp "Max new downloads this run [Enter to clear]: " limit
                       if [[ -z "$limit" ]]; then
                           OPTIONS[max_downloads]=""
                       elif [[ "$limit" =~ ^[0-9]+$ ]]; then
                           OPTIONS[max_downloads]="$limit"
                       else
                           printf "\n%b[ERROR] Must be a whole number.%b\n" "${RED}" "${NC}"; sleep 1; continue
                       fi ;;
                    5) if [[ -f "${OPTIONS[archive_file]}" ]]; then tail -n 10 "${OPTIONS[archive_file]}" || :; press_enter
                       else printf "%bArchive file does not exist yet.%b\n" "${YELLOW}" "${NC}"; sleep 1; fi; continue ;;
                    6) rm -f "${OPTIONS[archive_file]}"; printf "%bArchive deleted.%b\n" "${GREEN}" "${NC}"; sleep 1; continue ;;
                    *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}"; sleep 1; continue ;;
                esac
                printf "\n%bArchive settings updated.%b\n" "${GREEN}" "${NC}"; sleep 1 ;;
            3)
                printf "1) Title [ID].ext (default)\n2) Title.ext\n3) ID.ext\n4) Title - Channel [ID].ext\n5) Custom template\n\n"
                read -rp "Select sub-option [1-5]: " choice
                case "$choice" in
                    1) OPTIONS[output_template]="%(title)s [%(id)s].%(ext)s" ;;
                    2) OPTIONS[output_template]="%(title)s.%(ext)s" ;;
                    3) OPTIONS[output_template]="%(id)s.%(ext)s" ;;
                    4) OPTIONS[output_template]="%(title)s - %(uploader)s [%(id)s].%(ext)s" ;;
                    5) read -rp "Template: " name
                       [[ -n "$name" ]] && OPTIONS[output_template]="$name" ;;
                    *) printf "\n%bInvalid sub-option.%b\n" "${RED}" "${NC}"; sleep 1; continue ;;
                esac
                printf "\n%bTemplate set to: %s%b\n" "${GREEN}" "${OPTIONS[output_template]}" "${NC}"; sleep 1 ;;
            4) return ;;
            *) printf "%bInvalid option.%b\n" "${RED}" "${NC}"; sleep 1 ;;
        esac
    done
}

configure_advanced_settings() {
    while true; do
        local choice="" f="" s=""
        refresh_screen

        printf "%b=== Advanced Engine Settings ===%b\n\n" "${YELLOW}" "${NC}"
        printf "1) Verbose mode:                  [%s]\n" "$([[ "${OPTIONS[verbose]}" == "yes" ]] && echo "Enabled" || echo "Disabled")"
        printf "2) Restrict ASCII names:          [%s]\n" "$([[ "${OPTIONS[restrict_filenames]}" == "yes" ]] && echo "Enabled" || echo "Disabled")"
        printf "3) Preserve original upload date: [%s]\n" "$([[ "${OPTIONS[preserve_mtime]}" == "yes" ]] && echo "Enabled" || echo "Disabled")"
        printf "4) Ignore errors (playlist):      [%s]\n" "$([[ "${OPTIONS[ignore_errors]}" == "yes" ]] && echo "Enabled" || echo "Disabled")"
        printf "5) Concurrent fragments:           [%s]\n" "${OPTIONS[concurrent_fragments]}"
        printf "6) Sleep between requests:         [%ss]\n" "${OPTIONS[sleep_requests]}"
        printf "7) Back\n\n"

        read -rp "Select an option [1-7]: " choice
        printf "\n"

        case "$choice" in
            1) OPTIONS[verbose]=$([[ "${OPTIONS[verbose]}" == "yes" ]] && echo "no" || echo "yes") ;;
            2) OPTIONS[restrict_filenames]=$([[ "${OPTIONS[restrict_filenames]}" == "yes" ]] && echo "no" || echo "yes") ;;
            3) OPTIONS[preserve_mtime]=$([[ "${OPTIONS[preserve_mtime]}" == "yes" ]] && echo "no" || echo "yes") ;;
            4) OPTIONS[ignore_errors]=$([[ "${OPTIONS[ignore_errors]}" == "yes" ]] && echo "no" || echo "yes") ;;
            5)  read -rp "Fragments [1-10]: " f
                [[ "$f" =~ ^[0-9]+$ ]] && OPTIONS[concurrent_fragments]="$f" ;;
            6)  read -rp "Seconds: " s
                [[ "$s" =~ ^[0-9.]+$ ]] && OPTIONS[sleep_requests]="$s" ;;
            7) return ;;
            *) printf "%bInvalid option.%b\n" "${RED}" "${NC}"; sleep 1 ;;
        esac
    done
}

configure_live_stream() {
    local choice="" wait_val=""

    while true; do
        refresh_screen
        printf "%b=== Live Stream Recording ===%b\n\n" "${YELLOW}" "${NC}"
        printf "Record ongoing or upcoming live streams so you keep a copy even if the\n"
        printf "broadcaster deletes it afterwards.\n\n"
        printf "1) Record from the start: [%s]\n" "$([[ "${OPTIONS[live_from_start]}" == "yes" ]] && echo "Enabled" || echo "Disabled (joins from current point)")"
        printf "2) Wait for scheduled stream: [%s]\n" "${OPTIONS[wait_for_video]:-Disabled}"
        printf "3) Back\n\n"

        read -rp "Select an option [1-3]: " choice
        printf "\n"

        case "$choice" in
            1)
                OPTIONS[live_from_start]=$([[ "${OPTIONS[live_from_start]}" == "yes" ]] && echo "no" || echo "yes")
                printf "%bLive-from-start setting updated.%b\n" "${GREEN}" "${NC}"; sleep 1 ;;
            2)
                read -rp "Seconds between retries, e.g. 60 or 60-3600 [Enter to disable]: " wait_val
                if [[ -z "$wait_val" ]]; then
                    OPTIONS[wait_for_video]=""
                    printf "%bWait-for-video disabled.%b\n" "${GREEN}" "${NC}"
                elif [[ "$wait_val" =~ ^[0-9]+(-[0-9]+)?$ ]]; then
                    OPTIONS[wait_for_video]="$wait_val"
                    printf "%bWait-for-video set to: %s%b\n" "${GREEN}" "$wait_val" "${NC}"
                else
                    printf "%b[ERROR] Invalid value. Use SECONDS or MIN-MAX (e.g., 60-3600).%b\n" "${RED}" "${NC}"
                fi
                sleep 1 ;;
            3) return ;;
            *) printf "%bInvalid option.%b\n" "${RED}" "${NC}"; sleep 1 ;;
        esac
    done
}

view_config() {
    local part="" fmt_desc="" meta_str="" sub_str="" arch_str="" sys_str=""
    local audio_format_upper=""
    local meta_parts=() sub_actions=() arch_opts=() sys_opts=()

    _join_array() {
        local -n arr=$1
        local sep=$2
        local res=""
        for part in "${arr[@]}"; do
            [[ -n "$res" ]] && res+="$sep"
            res+="$part"
        done
        printf "%s" "$res"
    }

    refresh_screen

    printf "%b=== Download Summary ===%b\n" "${YELLOW}" "${NC}"
    printf "%bThis is how your download will be processed:%b\n\n" "${CYAN}" "${NC}"

    # 1. Content Type (Format & Audio)
    printf "%b• Content:%b " "${GREEN}" "${NC}"
    if [[ "${OPTIONS[extract_audio]}" == "yes" ]]; then
        audio_format_upper="${OPTIONS[audio_format]}"
        printf "Extracting audio as %b%s%b" "${YELLOW}" "${audio_format_upper^^}" "${NC}"

        if [[ "${OPTIONS[audio_quality]}" == "0" ]]; then
             printf " (Best Quality/Lossless)"
        else
             printf " (Quality: %s)" "${OPTIONS[audio_quality]}"
        fi
        printf "\n  %b(Video stream will be discarded)%b\n" "${RED}" "${NC}"

    elif [[ "${OPTIONS[format]}" == "bestaudio" ]]; then
        printf "Downloading %baudio only%b (no conversion)\n" "${YELLOW}" "${NC}"
    elif [[ "${OPTIONS[format]}" == "bestvideo" ]]; then
         printf "Downloading %bvideo only%b (no audio)\n" "${YELLOW}" "${NC}"
    else
        # Video + Audio
        fmt_desc="Best Video + Best Audio"
        if [[ "${OPTIONS[format]}" == "best" ]]; then fmt_desc="Best pre-merged (Single file)"; fi

        if [[ -n "${OPTIONS[max_res_sort]:-}" ]]; then
            fmt_desc="Video (Resolution capped via Sort to ${OPTIONS[max_res_sort]}p)"
        fi

        printf "%s\n" "$fmt_desc"

        # Container
        if [[ -n "${OPTIONS[remux_video]}" ]]; then
            printf "  %b↳ Remuxing container to: %s%b\n" "${CYAN}" "${OPTIONS[remux_video]^^}" "${NC}"
        elif [[ "${OPTIONS[merge_output_format]}" == "mkv" ]]; then
             printf "  %b↳ Merging into MKV container%b\n" "${CYAN}" "${NC}"
        fi
    fi

    # 2. Visuals (Thumbnail)
    printf "%b• Visuals:%b " "${GREEN}" "${NC}"
    if [[ "${OPTIONS[embed_thumbnail]}" == "yes" ]]; then
        if [[ "${OPTIONS[convert_thumbnails]}" == "jpg" ]]; then
            printf "Embedding thumbnail (Converted to JPG)\n"
        elif [[ "${OPTIONS[convert_thumbnails]}" == "png" ]]; then
             printf "Embedding thumbnail (Converted to PNG)\n"
        else
            printf "Embedding original thumbnail\n"
        fi
    else
        printf "No thumbnail\n"
    fi

    # 3. Metadata & Subtitles
    printf "%b• Data:%b    " "${GREEN}" "${NC}"

    if [[ "${OPTIONS[embed_metadata]}" == "yes" ]]; then
        meta_parts+=("Metadata (Includes Chapters)")
    elif [[ "${OPTIONS[embed_chapters]}" == "yes" ]]; then
        meta_parts+=("Chapters Only")
    fi
    [[ "${OPTIONS[embed_info_json]}" == "yes" ]] && meta_parts+=("JSON Info")

    if [ ${#meta_parts[@]} -eq 0 ]; then
        printf "Clean (No metadata)\n"
    else
        meta_str=$(_join_array meta_parts ", ")
        printf "%s\n" "$meta_str"
    fi

    # Subtitles detail
    if [[ "${OPTIONS[subtitles]}" == "yes" ]]; then
        printf "            Subtitles: %b%s%b " "${YELLOW}" "${OPTIONS[subtitles_lang]:-all}" "${NC}"
        [[ "${OPTIONS[embed_subs]}" == "yes" ]] && sub_actions+=("Embedded")
        [[ "${OPTIONS[write_subs]}" == "yes" ]] && sub_actions+=("Saved as file")

        sub_str=$(_join_array sub_actions "+")
        printf "(%s)\n" "$sub_str"
    fi

    # 4. Playlist
    printf "%b• Scope:%b   " "${GREEN}" "${NC}"
    if [[ "${OPTIONS[playlist_handling]}" == "no-playlist" ]]; then
        printf "Single video (Ignoring playlist if present)\n"
    elif [[ "${OPTIONS[playlist_handling]}" == "yes-playlist" ]]; then
        printf "Process Playlist"
        [[ -n "${OPTIONS[playlist_items]}" ]] && printf " (Items: %s)" "${OPTIONS[playlist_items]}"
        [[ "${OPTIONS[playlist_reverse]}" == "yes" ]] && printf " (Reverse Order)"
        printf "\n"
        if [[ "${OPTIONS[use_playlist_template]}" == "yes" ]]; then
             printf "            %b↳ Organizing in subfolders%b\n" "${CYAN}" "${NC}"
        fi
    else
        printf "Auto (Single video or Playlist)\n"
    fi

    # 4b. Live Streams
    if [[ "${OPTIONS[live_from_start]}" == "yes" || -n "${OPTIONS[wait_for_video]:-}" ]]; then
        printf "%b• Live:%b    " "${GREEN}" "${NC}"
        [[ "${OPTIONS[live_from_start]}" == "yes" ]] && printf "Recording from start "
        [[ -n "${OPTIONS[wait_for_video]:-}" ]] && printf "(Waiting for scheduled stream: %ss)" "${OPTIONS[wait_for_video]}"
        printf "\n"
    fi

    # 5. Output
    printf "%b• Target:%b  " "${GREEN}" "${NC}"
    printf "%b%s%b\n" "${BLUE}" "${OUTPUT_DIR:-Current Directory}" "${NC}"
    printf "            Template: %s\n" "${OPTIONS[output_template]}"

    if [[ "${OPTIONS[use_archive]}" == "yes" ]]; then
        printf "            %bTracking history in: %s%b\n" "${CYAN}" "${OPTIONS[archive_file]}" "${NC}"
        [[ "${OPTIONS[break_on_existing]}" == "yes" ]] && arch_opts+=("Stop on existing")
        [[ -n "${OPTIONS[max_downloads]}" ]] && arch_opts+=("Limit: ${OPTIONS[max_downloads]}")

        if [ ${#arch_opts[@]} -gt 0 ]; then
             arch_str=$(_join_array arch_opts ", ")
             printf "            %b↳ %s%b\n" "${YELLOW}" "$arch_str" "${NC}"
        fi
    fi

    # 6. Advanced
    printf "%b• System:%b  " "${GREEN}" "${NC}"
    [[ "${OPTIONS[verbose]}" == "yes" ]] && sys_opts+=("Verbose")
    [[ "${OPTIONS[restrict_filenames]}" == "yes" ]] && sys_opts+=("ASCII Filenames")
    [[ "${OPTIONS[preserve_mtime]}" == "yes" ]] && sys_opts+=("Preserve Original Date")
    [[ "${OPTIONS[ignore_errors]}" == "yes" ]] && sys_opts+=("Ignore Errors")

    if [ ${#sys_opts[@]} -gt 0 ]; then
        sys_str=$(_join_array sys_opts ", ")
    else
        sys_str="Default"
    fi

    printf "%s" "$sys_str"
    printf " [Fragments: %s | Sleep: %ss]\n" "${OPTIONS[concurrent_fragments]}" "${OPTIONS[sleep_requests]}"

    printf "\n"
    if [ ${#URL_LIST[@]} -eq 0 ]; then
         printf "%b[!] No URLs queued yet.%b\n" "${RED}" "${NC}"
    else
         printf "Ready to process %b%s URL(s)%b\n" "${GREEN}" "${#URL_LIST[@]}" "${NC}"
    fi

    press_enter
}

check_updates() {
    refresh_screen

    printf "%bChecking for updates and components...%b\n\n" "${YELLOW}" "${NC}"

    local script_dir setup_script
    script_dir=$(get_script_dir)
    setup_script="${script_dir}/setup.sh"

    if [[ -f "$setup_script" ]]; then
        bash "$setup_script" || :
    else
        _error "setup.sh not found next to download.sh (looked in $script_dir)"
    fi

    press_enter
}

# ==============================================================================
# MAIN MENU LOOP
# ==============================================================================

main_menu_loop() {
    local choice=""

    while true; do
        refresh_screen

        printf "%b=== MAIN MENU ===%b\n\n" "${GREEN}" "${NC}"

        local count_color="${GREEN}"
        if [ ${#URL_LIST[@]} -eq 0 ]; then
            count_color="${RED}"
        fi

        printf "1) Manage URLs (Total: %b%s%b)\n" "${count_color}" "${#URL_LIST[@]}" "${NC}"
        printf "\n"
        printf "2) Configure Output Directory\n"
        printf "3) Configure Post-Processing (Subtitles, Thumbnail, Metadata)\n"
        printf "4) Configure Format & Audio Extraction\n"
        printf "5) Configure Automation & Output Templates (Playlists, Archives, Limits)\n"
        printf "6) Configure Advanced Settings (Fragments, Sleep, Verbose)\n"
        printf "7) Configure Live Stream Recording (Save streams before they're deleted)\n"
        printf "8) View Current Configuration Summary\n"
        printf "9) Check For Updates\n"
        printf "10) Exit\n"
        printf "\n"
        printf "%b11) START DOWNLOAD%b\n" "${GREEN}" "${NC}"

        printf "\n"
        read -rp "Select an option [1-11]: " choice
        printf "\n"

        case "$choice" in
            1)  manage_urls ;;
            2)  manage_output_dir ;;
            3)  configure_post_processing ;;
            4)  configure_format_and_audio ;;
            5)  configure_automation_naming ;;
            6)  configure_advanced_settings ;;
            7)  configure_live_stream ;;
            8)  view_config ;;
            9)  check_updates ;;
            10) printf "%bBye!%b\n" "${YELLOW}" "${NC}"; exit 0 ;;
            11)
                if [ ${#URL_LIST[@]} -eq 0 ]; then
                    printf "%b[ERROR] No URLs in list. Please add at least one.%b\n" "${RED}" "${NC}"
                    sleep 2
                else
                    break
                fi
                ;;
            *)
                printf "%bInvalid option.%b\n" "${RED}" "${NC}"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# EXECUTION
# ==============================================================================

execute_ytdlp() {
    local path_to_bin="" ytdlp_bin="" ffmpeg_bin="" deno_bin="" sub_lang="" exit_code=0

    path_to_bin=$(get_bin_dir)
    ytdlp_bin="$path_to_bin/yt-dlp"
    ffmpeg_bin="$path_to_bin/ffmpeg"
    deno_bin="$path_to_bin/deno"

    local cmd=("$ytdlp_bin")

    # Common flags. Note: --retries/--fragment-retries are deliberately NOT
    # set here: yt-dlp's own defaults are already 10/10, so passing them
    # would just be noise. --socket-timeout and --concurrent-fragments ARE
    # real overrides of yt-dlp's defaults (unbounded / 1), so those stay.
    [[ "${OPTIONS[verbose]}" == "yes" ]] && cmd+=(--verbose)
    cmd+=(--socket-timeout 30)
    cmd+=(--sleep-requests "${OPTIONS[sleep_requests]}")
    cmd+=(--concurrent-fragments "${OPTIONS[concurrent_fragments]}")
    cmd+=(--ffmpeg-location "$ffmpeg_bin")
    cmd+=(--js-runtimes "deno:$deno_bin")

    # Output Path
    if [[ -n "$OUTPUT_DIR" ]]; then
        cmd+=(-P "$OUTPUT_DIR")
    fi

    # Format
    cmd+=(-f "${OPTIONS[format]}")

    if [[ -n "${OPTIONS[max_res_sort]:-}" ]]; then
        cmd+=(--format-sort "res:${OPTIONS[max_res_sort]}")
    fi

    # Playlist
    if [[ "${OPTIONS[playlist_handling]}" == "no-playlist" ]]; then
        cmd+=(--no-playlist)
    elif [[ "${OPTIONS[playlist_handling]}" == "yes-playlist" ]]; then
        cmd+=(--yes-playlist)
        [[ -n "${OPTIONS[playlist_items]}" ]] && cmd+=(-I "${OPTIONS[playlist_items]}")
        [[ "${OPTIONS[playlist_reverse]}" == "yes" ]] && cmd+=(--playlist-reverse)
    fi
    # "auto" (the default) adds no flag at all: yt-dlp's own behavior of
    # downloading the whole playlist only when the URL is a playlist link is
    # already the sane default, so there's nothing to override here.

    # Ignore errors (useful for playlists)
    if [[ "${OPTIONS[ignore_errors]}" == "yes" ]]; then
        cmd+=(-i)
    fi

    # Live streams (record from the start so the content survives even if deleted later)
    [[ "${OPTIONS[live_from_start]}" == "yes" ]] && cmd+=(--live-from-start)
    [[ -n "${OPTIONS[wait_for_video]:-}" ]] && cmd+=(--wait-for-video "${OPTIONS[wait_for_video]}")

    # Archive
    if [[ "${OPTIONS[use_archive]}" == "yes" ]]; then
        cmd+=(--download-archive "${OPTIONS[archive_file]}")
        [[ "${OPTIONS[break_on_existing]}" == "yes" ]] && cmd+=(--break-on-existing)
        [[ -n "${OPTIONS[max_downloads]}" ]] && cmd+=(--max-downloads "${OPTIONS[max_downloads]}")
    fi

    # Thumbnails
    if [[ "${OPTIONS[embed_thumbnail]}" == "yes" ]]; then
        cmd+=(--embed-thumbnail)
        [[ -n "${OPTIONS[convert_thumbnails]}" ]] && cmd+=(--convert-thumbnails "${OPTIONS[convert_thumbnails]}")
    fi

    if [[ -z "${OPTIONS[remux_video]}" && -n "${OPTIONS[merge_output_format]}" ]]; then
        cmd+=(--merge-output-format "${OPTIONS[merge_output_format]}")
    fi

    # Metadata
    if [[ "${OPTIONS[embed_metadata]}" == "yes" ]]; then
        cmd+=(--embed-metadata)
    elif [[ "${OPTIONS[embed_chapters]}" == "yes" ]]; then
        cmd+=(--embed-chapters)
    fi
    [[ "${OPTIONS[embed_info_json]}" == "yes" ]] && cmd+=(--embed-info-json)

    # Subtitles
    if [[ "${OPTIONS[subtitles]}" == "yes" ]]; then
        sub_lang="${OPTIONS[subtitles_lang]:-all}"
        [[ "${OPTIONS[embed_subs]}" == "yes" ]] && cmd+=(--embed-subs)
        [[ "${OPTIONS[write_subs]}" == "yes" ]] && cmd+=(--write-subs)
        cmd+=(--sub-langs "$sub_lang")
    fi

    # Audio
    if [[ "${OPTIONS[extract_audio]}" == "yes" ]]; then
        cmd+=(--extract-audio)
        [[ -n "${OPTIONS[audio_format]}" ]] && cmd+=(--audio-format "${OPTIONS[audio_format]}")
        [[ -n "${OPTIONS[audio_quality]}" ]] && cmd+=(--audio-quality "${OPTIONS[audio_quality]}")
    fi

    # Remux
    [[ -n "${OPTIONS[remux_video]}" ]] && cmd+=(--remux-video "${OPTIONS[remux_video]}")

    # Filenames / mtime. restrict-filenames deviates from yt-dlp's default so
    # it's always passed explicitly when enabled. mtime is the opposite case:
    # yt-dlp already defaults to --no-mtime, so we only ever need to pass the
    # explicit --mtime override, never --no-mtime.
    [[ "${OPTIONS[restrict_filenames]}" == "yes" ]] && cmd+=(--restrict-filenames)
    [[ "${OPTIONS[preserve_mtime]}" == "yes" ]] && cmd+=(--mtime)

    # Output Template
    if [[ "${OPTIONS[use_playlist_template]}" == "yes" ]]; then
        cmd+=(--output "%(playlist)s/%(playlist_index)02d - %(title)s.%(ext)s")
    else
        cmd+=(--output "${OPTIONS[output_template]}")
    fi

    # URLs
    cmd+=("${URL_LIST[@]}")

    # Execute
    printf "%b[INFO] Starting yt-dlp execution engine...%b\n\n" "${CYAN}" "${NC}"
    "${cmd[@]}" || exit_code=$?

    if (( exit_code != 0 )); then
        printf "\n%b[WARN] yt-dlp finished with exit code %d (some downloads may have failed).%b\n" "${YELLOW}" "$exit_code" "${NC}"
        return "$exit_code"
    else
        printf "\n%b[SUCCESS] All downloads completed successfully.%b\n" "${GREEN}" "${NC}"
        return 0
    fi
}

# ==============================================================================
# MAIN
# ==============================================================================

print_help() {
    printf "Usage: ./download.sh [OPTIONS] [URL...]\n\n"
    printf "  -q, --quick    Quick mode: use defaults and skip all menus. Never blocks\n"
    printf "                 on a prompt, so it's safe for cron/unattended use.\n"
    printf "  --live         Modifier: record from the actual start of a live stream\n"
    printf "                 (--live-from-start), instead of joining midway. Combine\n"
    printf "                 with --quick for a fully automated one-liner, e.g.:\n"
    printf "                   ./download.sh --quick --live URL\n"
    printf "  -h, --help     Show this help message\n"
    printf "\n"
    printf "yt-dlp-portable %s (last updated %s)\n" "$VERSION" "$LAST_UPDATED"
    printf "Note: the config file and the download-archive file are created in the\n"
    printf "CURRENT directory, not next to this script. cd into wherever you want\n"
    printf "your downloads and archive organized before running it.\n"
}

main() {
    # 1. Load/Init Config
    load_config
    init_defaults

    # 2. Parse Args
    local LIVE_MODE=false
    local code=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --quick|-q)
                QUICK_MODE=true
                shift
                ;;
            --live)
                LIVE_MODE=true
                shift
                ;;
            --help|-h)
                print_help
                exit 0
                ;;
            -*)
                _error "Unknown option: $1"
                _error "Run with --help for usage."
                exit 1
                ;;
            *)
                URL_LIST+=("$1")
                shift
                ;;
        esac
    done

    [[ "$LIVE_MODE" == "true" ]] && OPTIONS[live_from_start]="yes"

    # 3. Validation
    check_system
    # Initial banner
    show_banner

    printf "%b[INFO] Identity managed by yt-dlp internal handler%b\n\n" "${GREEN}" "${NC}"

    # 4. Mode Selection
    if [[ "$QUICK_MODE" == "true" ]]; then
        if [ ${#URL_LIST[@]} -eq 0 ]; then
            printf "%b[ERROR] No URLs in list for Quick Mode. Please add at least one URL as an argument.%b\n" "${RED}" "${NC}"
            exit 1
        fi
        printf "%b[INFO] Quick mode enabled. Processing queue using default configuration...%b\n" "${GREEN}" "${NC}"
        sleep 1
    else
        # Interactive Mode
        main_menu_loop
    fi

    # 5. Execute
    printf "\n"
    execute_ytdlp || code=$?
    if (( code != 0 )); then
        printf "\n"
        printf "%b[ERROR] yt-dlp finished with error code: %s%b\n" "${RED}" "$code" "${NC}"
        # These map to yt-dlp's actual exit semantics (verified against its
        # source): 1 covers the vast majority of real failures, 2 is either a
        # CLI argument-parsing error or an unexpected internal exception, and
        # 101 means it stopped on purpose rather than failing.
        case "$code" in
            1)   printf "%b↳ Download error: invalid URL, network issue, or an extractor problem. Enable Verbose mode for details.%b\n" "${YELLOW}" "${NC}" ;;
            2)   printf "%b↳ Argument error, or an unexpected internal yt-dlp error. Enable Verbose mode for details.%b\n" "${YELLOW}" "${NC}" ;;
            101) printf "%b↳ Stopped on purpose (hit --max-downloads or an existing archive entry), not necessarily a failure.%b\n" "${YELLOW}" "${NC}" ;;
            130) printf "%b↳ Interrupted.%b\n" "${YELLOW}" "${NC}" ;;
            *)   printf "%b↳ Check the error logs from yt-dlp printed above.%b\n" "${YELLOW}" "${NC}" ;;
        esac
        exit "$code"
    fi

    printf "%b[SUCCESS] Core execution process finished successfully.%b\n" "${GREEN}" "${NC}"
}


# ==============================================================================
# ENTRY POINT
# ==============================================================================

main "$@"
