#!/usr/bin/env bash
#
# stay_alive-toggle.sh
#
# Small toggle UI for the stay_alive helper.
# - If stay-alive is active, toggles it OFF
# - If inactive, shows a small menu to pick a duration and enables it
#
# Uses: wofi (preferred) -> rofi -> zenity -> terminal fallback
# Calls: stay_alive.sh (must be in the same folder)
#
# Examples:
#  - Click the SwayNC button (this script) to toggle / enable (prompt for duration)
#  - Or run: SWAYNC_UI=rofi stay_alive-toggle.sh
#
set -euo pipefail

# Resolve script dir
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
STAY="$SCRIPT_DIR/stay_alive.sh"

# Logging
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/stay_alive-toggle.log"
echo "[$(date -Iseconds)] invoked stay_alive-toggle (UI=${SWAYNC_UI:-auto})" >>"$LOG" 2>/dev/null || true
log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG" 2>/dev/null || true; }

# Notification helper (best-effort)
notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@"
  else
    # print to stdout as fallback
    printf '%s\n' "$*"
  fi
}

# UI detection (allow explicit SWAYNC_UI override)
detect_ui() {
  ui="${SWAYNC_UI:-}"
  ui="${ui,,}"   # lowercase
  if [ -z "$ui" ]; then
    if command -v wofi >/dev/null 2>&1; then
      ui="wofi"
    elif command -v rofi >/dev/null 2>&1; then
      ui="rofi"
    elif command -v zenity >/dev/null 2>&1; then
      ui="zenity"
    else
      ui="none"
    fi
  fi
  echo "$ui"
}

# Present a small list and return the selected item (or empty string)
prompt_menu() {
  prompt="$1"; shift
  options=("$@")
  ui="$(detect_ui)"

  case "$ui" in
    wofi)
      printf '%s\n' "${options[@]}" | wofi --dmenu -i --prompt "$prompt"
      ;;
    rofi)
      printf '%s\n' "${options[@]}" | rofi -dmenu -i -p "$prompt"
      ;;
    zenity)
      # zenity list: pass as arguments
      # If zenity returns non-zero (cancel), we return empty
      if sel="$(zenity --list --title="$prompt" --column="$prompt" "${options[@]}" 2>/dev/null)"; then
        printf '%s' "$sel"
      else
        printf ''
      fi
      ;;
    none)
      # Terminal fallback: print options then read
      printf '%s\n' "${options[@]}"
      read -rp "$prompt: " answer
      printf '%s' "$answer"
      ;;
  esac
}

prompt_input() {
  prompt="$1"
  ui="$(detect_ui)"
  case "$ui" in
    wofi)
      wofi --dmenu -i --prompt "$prompt"
      ;;
    rofi)
      rofi -dmenu -i -p "$prompt"
      ;;
    zenity)
      zenity --entry --title="$prompt" --text="$prompt" 2>/dev/null || echo ""
      ;;
    none)
      read -rp "$prompt: " ans
      echo "$ans"
      ;;
  esac
}

# Check stay helper present
if [ ! -x "$STAY" ]; then
  notify "Stay Alive" "Helper not found: $STAY"
  log "ERROR: helper missing: $STAY"
  exit 1
fi

# Query status
status="$("$STAY" status 2>/dev/null || echo \"off\")"
status="${status:-off}"

# If currently ON -> toggle OFF
if [[ "$status" == on* ]]; then
  "$STAY" off >/dev/null 2>&1 || true
  notify "Stay Alive" "Disabled"
  log "Disabled stay-alive (was: $status)"
  exit 0
fi

# Otherwise, inactive -> show durations to enable
options=("15m" "1h" "4h" "8h" "24h" "forever" "Custom..." "Cancel")
choice="$(prompt_menu 'Stay alive duration' "${options[@]}")"
choice="${choice:-}"

if [ -z "$choice" ] || [ "$choice" = "Cancel" ]; then
  log "User cancelled stay-alive menu"
  exit 0
fi

# Custom input
if [ "$choice" = "Custom..." ]; then
  custom="$(prompt_input 'Custom duration (e.g. 20m, 1h, 3600 (seconds), or forever)')"
  custom="${custom:-}"
  if [ -z "$custom" ]; then
    notify "Stay Alive" "Cancelled (no duration given)"
    log "Custom duration cancelled"
    exit 0
  fi
  choice="$custom"
fi

# Validate a bit: accept either <number>[s|m|h|d], or plain number (minutes), or 'forever'/'0'
# We will pass the user's string to stay_alive.sh directly (it can parse 15m, 1h, etc.)
if ! "$STAY" on "$choice" >/dev/null 2>&1; then
  notify "Stay Alive" "Failed to enable stay-alive for \"$choice\""
  log "Failed to enable stay-alive for \"$choice\""
  exit 1
else
  notify "Stay Alive" "Enabled for $choice"
  log "Enabled stay-alive for $choice"
  exit 0
fi
