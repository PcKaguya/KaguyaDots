#!/bin/bash
# Scripts for refreshing Hyprland + components (waybar, swaync, ags, wallust, hyprpm)

#  _   _ _____ ____    _  _____ _____
# | | | | ____/ ___|  / \|_   _| ____|     /\_/\
# | |_| |  _|| |     / _ \ | | |  _|      ( o.o )
# |  _  | |__| |___ / ___ \| | | |___      > ^ <
# |_| |_|_____\____/_/   \_\_| |_____|

SCRIPTSDIR="$HOME/.config/hypr/scripts"
UserScripts="$HOME/.config/hypr/UserScripts"

# --- helpers ---
file_exists() {
  [[ -e "$1" ]]
}

# --- kill processes safely ---
_ps=(waybar rofi swaync ags)
for _prs in "${_ps[@]}"; do
  if pidof "$_prs" >/dev/null 2>&1; then
    pkill -x "$_prs" 2>/dev/null || true
  fi
done

# quit ags gracefully if present
if command -v ags >/dev/null 2>&1; then
  ags -q || true
fi

# --- restart waybar ---
sleep 1
WAYBAR_DISABLE_DBUS=1 waybar >~/.cache/waybar.log 2>&1 &

# --- restart swaync ---
sleep 0.5
swaync >/dev/null 2>&1 &
swaync-client --reload-config >/dev/null 2>&1 || true

# --- restart ags if available ---
if command -v ags >/dev/null 2>&1; then
  ags >/dev/null 2>&1 &
fi

# Relaunching rainbow borders if the script exists
sleep 1
if file_exists "${UserScripts}/RainbowBorders.sh"; then
  "${UserScripts}/RainbowBorders.sh" &
fi

# --- optional Quickshell restart ---
# pkill -x qs && qs >/dev/null 2>&1 &

# --- refresh Hyprland config ---
hyprctl reload >/dev/null 2>&1 || true

# --- hyprpm reload if requested ---
if [[ "$1" == "hyprpm" ]]; then
  if [[ -n "$2" ]]; then
    echo ":: Reloading hyprpm plugin: $2"
    hyprpm reload "$2"
  else
    echo ":: Reloading all hyprpm plugins"
    hyprpm reload all
  fi
fi

notify-send -u low "System Reloaded Successfully"
exit 0
