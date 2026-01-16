#!/usr/bin/env bash
# WallpaperRandom.sh
# Pick a random wallpaper from a directory and set it with swww (preferred),
# falling back to swaybg if necessary. Also runs wallust refresh + system refresh.
#
# Usage:
#   WallpaperRandom.sh [WALLPAPER_DIR]
#
# Defaults:
#   WALLPAPER_DIR="$HOME/Pictures/wallpapers"
#
# This script mirrors behavior used by the KaguyaDots/Hyprland setup:
# - sets wallpaper on the focused monitor (uses hyprctl to detect)
# - triggers color extraction (`WallustSwww.sh`) and UI refresh (`Refresh.sh`)
# - notifies the user of success/failure

set -euo pipefail

# Configuration
WALL_DIR="${1:-$HOME/Pictures/wallpapers}"
SCRIPTSDIR="$HOME/.config/hypr/scripts"
USERSCRIPTS="$HOME/.config/hypr/UserScripts"
ICON="$HOME/.config/swaync/images/bell.png"

# swww transition config
FPS=60
TYPE="any"
DURATION=2
SWWW_PARAMS="--transition-fps $FPS --transition-type $TYPE --transition-duration $DURATION"

# Determine focused monitor (fall back to first monitor if detection fails)
focused_monitor=$(hyprctl monitors 2>/dev/null | awk '/^Monitor/{name=$2} /focused: yes/{print name}')
if [ -z "$focused_monitor" ]; then
  focused_monitor=$(hyprctl monitors 2>/dev/null | awk '/^Monitor/{print $2; exit}' || true)
fi

# Ensure directory exists
if [ ! -d "$WALL_DIR" ]; then
  notify-send -u critical -i "$ICON" "WallpaperRandom" "Wallpaper directory not found: $WALL_DIR"
  exit 1
fi

# Build list of image files (handles spaces/newlines)
mapfile -d '' PICS < <(find "$WALL_DIR" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" \
  \) -print0)

if [ "${#PICS[@]}" -eq 0 ]; then
  notify-send -u critical -i "$ICON" "WallpaperRandom" "No images found in $WALL_DIR"
  exit 1
fi

# Pick a random image
RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"

# Apply wallpaper using swww if available
if command -v swww >/dev/null 2>&1; then
  # Ensure swww daemon is running
  swww query >/dev/null 2>&1 || swww-daemon --format xrgb >/dev/null 2>&1 || true

  if [ -n "$focused_monitor" ]; then
    swww img -o "$focused_monitor" "$RANDOM_PIC" $SWWW_PARAMS || {
      notify-send -u critical -i "$ICON" "WallpaperRandom" "Failed to set wallpaper via swww"
      exit 1
    }
  else
    # No focused monitor found; set for all outputs
    swww img "$RANDOM_PIC" $SWWW_PARAMS || {
      notify-send -u critical -i "$ICON" "WallpaperRandom" "Failed to set wallpaper via swww"
      exit 1
    }
  fi
elif command -v swaybg >/dev/null 2>&1; then
  # Fallback to swaybg (no transitions)
  swaybg -i "$RANDOM_PIC" -m fill >/dev/null 2>&1 || {
    notify-send -u critical -i "$ICON" "WallpaperRandom" "Failed to set wallpaper via swaybg"
    exit 1
  }
else
  notify-send -u critical -i "$ICON" "WallpaperRandom" "No wallpaper tool found (swww/swaybg)"
  exit 1
fi

# Give swww a moment to settle
sleep 0.5

# Run wallust/color extraction if the helper exists
if [ -x "$SCRIPTSDIR/WallustSwww.sh" ]; then
  "$SCRIPTSDIR/WallustSwww.sh" >/dev/null 2>&1 || true
fi

# Refresh UI components (waybar, swaync, etc.)
if [ -x "$SCRIPTSDIR/Refresh.sh" ]; then
  "$SCRIPTSDIR/Refresh.sh" >/dev/null 2>&1 || true
fi

# Notify user
BASENAME="$(basename "$RANDOM_PIC")"
if command -v notify-send >/dev/null 2>&1; then
  notify-send -u low -i "$ICON" "Wallpaper Randomizer" "Set wallpaper: $BASENAME"
else
  echo "Wallpaper set: $RANDOM_PIC"
fi

exit 0
