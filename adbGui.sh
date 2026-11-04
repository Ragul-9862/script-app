#!/usr/bin/env bash
# Linux-friendly equivalent of adbGui.ps1
# Features:
# - Detect ADB
# - List connected Android devices
# - List installed apps
# - Mirror device screen via scrcpy
#
# Requires: adb and scrcpy (or install via distro package manager)

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADS_DIR="${HOME}/Downloads"

ADB_BIN=""
SCRCPY_BIN=""

choose_picker() {
  if command -v dialog >/dev/null 2>&1; then
    return 0
  elif command -v zenity >/dev/null 2>&1; then
    return 1
  else
    return 2
  fi
}

find_adb() {
  if [[ -n "${ADB_BIN}" ]]; then
    return 0
  fi

  local candidates=(
    "$(command -v adb 2>/dev/null)"
    "${ANDROID_HOME}/platform-tools/adb"
    "${ANDROID_SDK_ROOT}/platform-tools/adb"
    "${HOME}/Android/Sdk/platform-tools/adb"
    "/opt/android-sdk/platform-tools/adb"
    "/usr/lib/android-sdk/platform-tools/adb"
    "/usr/local/android-sdk/platform-tools/adb"
  )

  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -x "$c" ]]; then
      ADB_BIN="$c"
      return 0
    fi
  done

  return 1
}

find_scrcpy() {
  if [[ -n "${SCRCPY_BIN}" ]]; then
    return 0
  fi

  local candidates=(
    "$(command -v scrcpy 2>/dev/null)"
    "${HOME}/.local/bin/scrcpy"
    "/usr/bin/scrcpy"
    "/usr/local/bin/scrcpy"
    "/snap/bin/scrcpy"
    "/opt/scrcpy/scrcpy"
    "${SCRIPT_DIR}/scrcpy"
  )

  for c in "${candidates[@]}"; do
    if [[ -n "$c" && -x "$c" ]]; then
      SCRCPY_BIN="$c"
      return 0
    fi
  done

  return 1
}

install_scrcpy() {
  echo "scrcpy not found. Installing..."

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update && sudo apt-get install -y scrcpy
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y scrcpy
  elif command -v pacman >/dev/null 2>&1; then
    sudo pacman -S --noconfirm scrcpy
  elif command -v zypper >/dev/null 2>&1; then
    sudo zypper install -y scrcpy
  else
    echo "Unable to auto-install scrcpy on this Linux distro."
    echo "Please install it manually, then rerun this script."
    echo "Typical packages: scrcpy (Debian/Ubuntu), scrcpy (Fedora), or via GitHub releases."
    exit 1
  fi

  find_scrcpy || {
    echo "scrcpy installation finished but binary is still not available on PATH."
    exit 1
  }
}

get_devices() {
  "$ADB_BIN" devices 2>/dev/null | awk '$2=="device" {print $1}'
}

select_device() {
  local devices=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && devices+=("$line")
  done < <(get_devices)

  if [[ ${#devices[@]} -eq 0 ]]; then
    echo "No devices found. Check USB debugging and reconnect the device."
    return 1
  fi

  if command -v dialog >/dev/null 2>&1; then
    local menu_options=()
    local index=1
    for d in "${devices[@]}"; do
      menu_options+=("$index" "$d")
      index=$((index + 1))
    done

    local choice
    choice=$(dialog --menu "Select Android device" 20 60 12 "${menu_options[@]}" 3>&1 1>&2 2>&3)
    if [[ -n "$choice" ]]; then
      local selected="${devices[$((choice - 1))]}"
      printf '%s\n' "$selected"
      return 0
    fi
    return 1
  elif command -v zenity >/dev/null 2>&1; then
    local selected
    selected=$(zenity --list --title="Android device" --column="Device" "${devices[@]}" 2>/dev/null)
    if [[ -n "$selected" ]]; then
      printf '%s\n' "$selected"
      return 0
    fi
    return 1
  fi

  echo "Available devices:"
  local i=1
  for d in "${devices[@]}"; do
    echo "$i) $d"
    i=$((i + 1))
  done

  printf "Choose device [1-%s]: " "${#devices[@]}"
  read -r choice
  if [[ "$choice" =~ ^[1-9][0-9]*$ && "$choice" -ge 1 && "$choice" -le "${#devices[@]}" ]]; then
    printf '%s\n' "${devices[$((choice - 1))]}"
    return 0
  fi

  echo "Invalid selection."
  return 1
}

list_apps() {
  local device_id="$1"
  "$ADB_BIN" -s "$device_id" shell pm list packages 2>/dev/null | sed 's/^package://g' | sort
}

main_menu() {
  local selected_device=""
  while true; do
    clear
    echo "ADB App Manager (Linux)"
    echo "1) Refresh devices"
    echo "2) List installed apps"
    echo "3) Mirror screen"
    echo "4) Exit"
    printf "Select option: "
    read -r choice

    case "$choice" in
      1)
        if ! find_adb; then
          echo "adb not found. Install Android platform-tools or add adb to PATH."
          exit 1
        fi
        echo "Connected devices:"
        get_devices | sed '/^$/d' || true
        echo "Press Enter to continue..."
        read -r _
        ;;
      2)
        if ! find_adb; then
          echo "adb not found. Install Android platform-tools or add adb to PATH."
          exit 1
        fi
        selected_device="$(select_device || true)"
        if [[ -z "$selected_device" ]]; then
          echo "No device selected."
          echo "Press Enter to continue..."
          read -r _
          continue
        fi
        echo "Fetching apps for $selected_device..."
        list_apps "$selected_device"
        echo "Press Enter to continue..."
        read -r _
        ;;
      3)
        if ! find_adb; then
          echo "adb not found. Install Android platform-tools or add adb to PATH."
          exit 1
        fi
        if ! find_scrcpy; then
          install_scrcpy
        fi
        selected_device="$(select_device || true)"
        if [[ -z "$selected_device" ]]; then
          echo "No device selected."
          echo "Press Enter to continue..."
          read -r _
          continue
        fi
        echo "Launching scrcpy for $selected_device..."
        "$SCRCPY_BIN" -s "$selected_device"
        ;;
      4)
        exit 0
        ;;
      *)
        echo "Invalid option."
        echo "Press Enter to continue..."
        read -r _
        ;;
    esac
  done
}

if ! find_adb; then
  echo "ADB was not found on this system."
  echo "Please install Android platform-tools and ensure adb is in PATH."
  echo "Example: sudo apt install adb"
  exit 1
fi

main_menu
