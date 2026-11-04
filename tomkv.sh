#!/usr/bin/env bash
# Linux-friendly equivalent of tomkv.ps1
# Features:
# - Video + audio -> MKV
# - Audio only -> MKA
# - Select multiple audio tracks
# - Choose one default audio track
# - Output to ~/Downloads
#
# Requires: ffmpeg installed and available in PATH

set -u

DOWNLOADS_DIR="${HOME}/Downloads"
mkdir -p "$DOWNLOADS_DIR"

ffmpeg_bin=""

find_ffmpeg() {
  if [[ -n "$ffmpeg_bin" ]]; then
    return 0
  fi

  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg_bin="$(command -v ffmpeg)"
    return 0
  fi

  if [[ -x "${HOME}/bin/ffmpeg" ]]; then
    ffmpeg_bin="${HOME}/bin/ffmpeg"
    return 0
  fi

  return 1
}

pick_file() {
  local title="$1"
  local default_dir="${2:-$HOME}"

  if command -v zenity >/dev/null 2>&1; then
    zenity --file-selection --title="$title" --filename="$default_dir/" 2>/dev/null
  elif command -v kdialog >/dev/null 2>&1; then
    kdialog --getopenfilename "$default_dir" "$title" 2>/dev/null
  elif command -v dialog >/dev/null 2>&1; then
    local file
    file=$(dialog --stdout --title "$title" --fselect "$default_dir/" 15 70 2>/dev/null)
    printf '%s\n' "$file"
  else
    printf "Enter path for %s: " "$title"
    read -r file
    printf '%s\n' "$file"
  fi
}

pick_multiple_audio_files() {
  local picked=()
  local file=''

  while true; do
    if command -v zenity >/dev/null 2>&1; then
      file=$(zenity --file-selection --multiple --separator='\n' --title='Select audio files' --filename="$HOME/" 2>/dev/null)
    elif command -v kdialog >/dev/null 2>&1; then
      file=$(kdialog --multiple --getopenfilename "$HOME" "Select audio files" 2>/dev/null)
    elif command -v dialog >/dev/null 2>&1; then
      echo "Select audio files one by one. Press Esc to finish."
      file=$(dialog --stdout --title 'Select audio file' --fselect "$HOME/" 15 70 2>/dev/null)
      if [[ -z "$file" ]]; then
        break
      fi
      picked+=("$file")
      printf "Add another file? [y/N]: "
      read -r add_more
      if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
        break
      fi
      continue
    else
      echo "Add audio file (blank to finish):"
      printf "Path: "
      read -r file
      if [[ -z "$file" ]]; then
        break
      fi
      if [[ -f "$file" ]]; then
        picked+=("$file")
      else
        echo "File not found: $file"
      fi
      printf "Add another file? [y/N]: "
      read -r add_more
      if [[ ! "$add_more" =~ ^[Yy]$ ]]; then
        break
      fi
      continue
    fi

    if [[ -n "$file" ]]; then
      while IFS= read -r item; do
        [[ -n "$item" ]] && picked+=("$item")
      done < <(printf '%s\n' "$file" | tr '\n' '\n')
    fi

    if ! command -v zenity >/dev/null 2>&1 && ! command -v kdialog >/dev/null 2>&1; then
      continue
    fi

    if [[ -n "$file" ]]; then
      break
    fi
  done

  if [[ ${#picked[@]} -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${picked[@]}"
}

unique_output_path() {
  local base="$1"
  local ext="$2"
  local path="${DOWNLOADS_DIR}/${base}.${ext}"
  local i=1
  while [[ -e "$path" ]]; do
    path="${DOWNLOADS_DIR}/${base} (${i}).${ext}"
    i=$((i + 1))
  done
  printf '%s\n' "$path"
}

choose_mode() {
  echo "Select mode:"
  echo "1) Video + audio -> MKV"
  echo "2) Audio only -> MKA"
  printf "Choice [1/2]: "
  read -r mode
  case "$mode" in
    1) printf 'video\n';;
    2) printf 'audio\n';;
    *) echo "Invalid choice."; exit 1 ;;
  esac
}

show_default_selection() {
  local name="$1"
  local i=1
  for item in "$@"; do
    if [[ "$i" -eq 1 ]]; then
      i=$((i + 1))
      continue
    fi
    if [[ "$i" -eq 2 ]]; then
      i=$((i + 1))
      continue
    fi
    echo "$item"
    i=$((i + 1))
  done
}

build_video_mkv() {
  local video_file="$1"
  shift
  local out_path="$1"
  shift
  local audio_files=("$@")

  local default_index=0
  local ff_args=("-y" "-hide_banner")
  ff_args+=("-i" "$video_file")

  local idx=0
  for f in "${audio_files[@]}"; do
    ff_args+=("-i" "$f")
    idx=$((idx + 1))
  done

  ff_args+=("-map" "0:v:0")
  local a_index=1
  for ((i=0; i<${#audio_files[@]}; i++)); do
    ff_args+=("-map" "$((i + 1))":"a:0")
    ff_args+=("-metadata:s:a:${i}" "title=Track $((i + 1))")
    ff_args+=("-disposition:a:${i}" "default")
    if [[ "$i" -eq "$default_index" ]]; then
      ff_args+=("-metadata:s:a:${i}" "title=Track $((i + 1))")
    fi
    a_index=$((a_index + 1))
  done

  # Keep original video audio if desired in a later enhancement.
  ff_args+=("-c:v" "copy")
  ff_args+=("-c:a" "copy")
  ff_args+=("-movflags" "+faststart")
  ff_args+=("$out_path")

  "${ffmpeg_bin}" "${ff_args[@]}" || {
    echo "ffmpeg failed while creating MKV."
    exit 1
  }
}

build_audio_mka() {
  local out_path="$1"
  shift
  local audio_files=("$@")

  local ff_args=("-y" "-hide_banner")
  for f in "${audio_files[@]}"; do
    ff_args+=("-i" "$f")
  done

  local map_args=()
  for ((i=0; i<${#audio_files[@]}; i++)); do
    map_args+=("-map" "$((i))":"a:0")
    ff_args+=("-metadata:s:a:${i}" "title=Track $((i + 1))")
    if [[ "$i" -eq 0 ]]; then
      ff_args+=("-disposition:a:${i}" "default")
    fi
  done

  ff_args+=("${map_args[@]}")
  ff_args+=("-c:a" "copy")
  ff_args+=("$out_path")

  "${ffmpeg_bin}" "${ff_args[@]}" || {
    echo "ffmpeg failed while creating MKA."
    exit 1
  }
}

main() {
  if ! find_ffmpeg; then
    echo "ffmpeg not found. Install it first. Example: sudo apt install ffmpeg"
    exit 1
  fi

  local mode
  mode="$(choose_mode)"

  local video_file=""
  local audio_files=()
  local output_ext="mkv"
  local output_name="combined"

  if [[ "$mode" == "video" ]]; then
    video_file="$(pick_file "Select video file" "$HOME")"
    if [[ -z "$video_file" || ! -f "$video_file" ]]; then
      echo "Video file not selected or missing."
      exit 1
    fi

    echo "Select one or more audio files."
    audio_files=( $(pick_multiple_audio_files) )
    if [[ ${#audio_files[@]} -eq 0 ]]; then
      echo "No audio files selected."
      exit 1
    fi

    output_name="$(basename "${video_file%.*}")"
    output_ext="mkv"
    local out_path
    out_path="$(unique_output_path "$output_name" "$output_ext")"
    echo "Output: $out_path"
    build_video_mkv "$video_file" "$out_path" "${audio_files[@]}"
  else
    echo "Select one or more audio files for MKA."
    audio_files=( $(pick_multiple_audio_files) )
    if [[ ${#audio_files[@]} -eq 0 ]]; then
      echo "No audio files selected."
      exit 1
    fi

    output_name="audio_mix"
    output_ext="mka"
    local out_path
    out_path="$(unique_output_path "$output_name" "$output_ext")"
    echo "Output: $out_path"
    build_audio_mka "$out_path" "${audio_files[@]}"
  fi

  echo "Finished."
}

main "$@"
