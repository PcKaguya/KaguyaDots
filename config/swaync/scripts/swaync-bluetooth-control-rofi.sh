#!/usr/bin/env bash
# swaync-bluetooth-control-rofi.sh
#
# A tiny wrapper that forces the Bluetooth control script to use rofi as the
# dmenu-style UI. If rofi is not available it will fall back to the
# main script's auto-detection (wofi/rofi/zenity).
#
# Usage:
#   swaync-bluetooth-control-rofi.sh [args...]
#
# This wrapper forwards all arguments to the main script and sets
# SWAYNC_UI=rofi in the environment so the main script will prefer rofi.
#
# Log output is appended to: ${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync/bt-rofi.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
MAIN_SCRIPT="$SCRIPT_DIR/swaync-bluetooth-control.sh"

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bt-rofi.log"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG_FILE"
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<EOF
Usage: $(basename "$0") [args...]
Forces the Bluetooth control script to use rofi as the UI by setting SWAYNC_UI=rofi.
If rofi is not installed, the wrapper falls back to running the main script
without forcing the UI (the main script will auto-detect/choose another UI).
Any arguments are forwarded to the main script.
EOF
  exit 0
fi

log "wrapper invoked (args: $*) TTY=$(tty 2>/dev/null || echo none) SWAYNC_UI=${SWAYNC_UI:-not-set}"

if [ ! -x "$MAIN_SCRIPT" ]; then
  log "ERROR: main script not found or not executable: $MAIN_SCRIPT"
  >&2 echo "ERROR: main script not found or not executable: $MAIN_SCRIPT"
  exit 2
fi

# If rofi is missing, fall back to main script's detection
if ! command -v rofi >/dev/null 2>&1; then
  log "rofi not found, falling back to main script UI detection"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "Bluetooth" "rofi not found — opening default UI"
  fi
  exec "$MAIN_SCRIPT" "$@"
fi

# Force rofi
export SWAYNC_UI="rofi"
log "forcing SWAYNC_UI=rofi and exec-ing main script"

# Exec the main script with the environment variable set
exec env SWAYNC_UI=rofi "$MAIN_SCRIPT" "$@"
