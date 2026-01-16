#!/usr/bin/env bash
# WaybarStyles.sh - Toggle or select Waybar style (CSS) and reload Waybar.
#
# Usage:
#   WaybarStyles.sh           -> interactive menu (rofi/dmenu/fallback prompt)
#   WaybarStyles.sh --menu    -> same as no-arg
#   WaybarStyles.sh --toggle  -> cycle to next available style
#   WaybarStyles.sh --set X   -> set style to X (basename or full path)
#   WaybarStyles.sh --list    -> print available styles
#   WaybarStyles.sh --current -> print currently active style
#   WaybarStyles.sh --help    -> show this help
#
# Notes:
#  - Styles are expected under: ~/.config/waybar/style/*.css
#  - The active style is the symlink: ~/.config/waybar/style.css
#  - After changing the style, the script sends SIGUSR2 to reload Waybar, or starts it if not running.

set -uo pipefail

STYLE_DIR="$HOME/.config/waybar/style"
STYLE_LINK="$HOME/.config/waybar/style.css"

# Print usage/help
usage() {
  cat <<EOF
Usage: $(basename "$0") [--menu|--toggle|--set STYLE|--list|--current|--help]
Toggle or choose Waybar's CSS style from files in: $STYLE_DIR
EOF
  exit 0
}

# Return list of available style basenames
list_styles() {
  if [ ! -d "$STYLE_DIR" ]; then
    return 1
  fi
  local f
  local -a out=()
  for f in "$STYLE_DIR"/*.css; do
    [ -e "$f" ] || continue
    out+=("$(basename "$f")")
  done
  if [ "${#out[@]}" -eq 0 ]; then
    return 1
  fi
  printf '%s\n' "${out[@]}"
}

# Return currently set style basename (may be empty)
current_style() {
  if [ -L "$STYLE_LINK" ]; then
    basename "$(readlink -f "$STYLE_LINK")"
  elif [ -f "$STYLE_LINK" ]; then
    basename "$STYLE_LINK"
  else
    printf '%s\n' ""
  fi
}

# Set style by basename or full path
set_style() {
  local choice="$1"
  local target
  if [ -z "$choice" ]; then
    echo "No style given" >&2
    return 1
  fi

  if [[ "$choice" == */* ]]; then
    target="$choice"
  else
    target="$STYLE_DIR/$choice"
  fi

  if [ ! -e "$target" ]; then
    echo "Style not found: $choice" >&2
    return 1
  fi

  mkdir -p "$(dirname "$STYLE_LINK")"
  ln -sf "$target" "$STYLE_LINK"

  # Reload waybar if running, otherwise start it
  if command -v pidof >/dev/null 2>&1 && pidof waybar >/dev/null 2>&1; then
    pkill -SIGUSR2 waybar 2>/dev/null || true
  else
    # Start waybar in background (non-blocking)
    if command -v waybar >/dev/null 2>&1; then
      WAYBAR_DISABLE_DBUS=1 waybar >"$HOME/.cache/waybar.log" 2>&1 & disown
    fi
  fi

  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u low "Waybar style set" "$(basename "$target")"
  else
    echo "Waybar style set -> $(basename "$target")"
  fi
  return 0
}

# Interactive menu: rofi -> dmenu -> prompt fallback
menu() {
  local -a styles
  mapfile -t styles < <(list_styles 2>/dev/null || true)
  if [ "${#styles[@]}" -eq 0 ]; then
    echo "No styles available in $STYLE_DIR" >&2
    return 1
  fi

  local choice=""
  if command -v rofi >/dev/null 2>&1; then
    choice=$(printf '%s\n' "${styles[@]}" | rofi -dmenu -i -p "Waybar style")
  elif command -v dmenu >/dev/null 2>&1; then
    choice=$(printf '%s\n' "${styles[@]}" | dmenu -i -p "Waybar style")
  else
    printf '%s\n' "${styles[@]}"
    printf 'Enter style to set: ' >&2
    read -r choice
  fi

  # If user cancels, choice may be empty
  if [ -z "$choice" ]; then
    return 0
  fi

  set_style "$choice"
}

# Cycle to the next style in the list (wraps)
toggle() {
  local -a styles
  mapfile -t styles < <(list_styles 2>/dev/null || true)
  if [ "${#styles[@]}" -eq 0 ]; then
    echo "No styles to toggle" >&2
    return 1
  fi

  local cur
  cur=$(current_style)
  local idx=-1
  local i
  for i in "${!styles[@]}"; do
    if [ "${styles[$i]}" = "$cur" ]; then
      idx="$i"
      break
    fi
  done

  if [ "$idx" -lt 0 ]; then
    set_style "${styles[0]}"
  else
    local next=$(( (idx + 1) % ${#styles[@]} ))
    set_style "${styles[$next]}"
  fi
}

# Parse args
if [ "$#" -eq 0 ]; then
  # default: interactive menu
  menu
  exit $?
fi

case "$1" in
  --menu|-m)
    menu
    ;;
  --toggle|-t|--cycle)
    toggle
    ;;
  --set)
    if [ -z "${2:-}" ]; then
      echo "Usage: $0 --set STYLE" >&2
      exit 2
    fi
    set_style "$2"
    ;;
  --list|-l)
    list_styles || { echo "No styles found in $STYLE_DIR" >&2; exit 1; }
    ;;
  --current)
    current_style
    ;;
  --help|-h)
    usage
    ;;
  *)
    echo "Unknown arg: $1" >&2
    usage
    ;;
esac

exit 0
