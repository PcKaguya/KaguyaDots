#!/usr/bin/env bash
#
# swaync-wifi-control.sh
#
# Wofi-based Wi-Fi manager for SwayNC
# - Uses wofi (falling back to rofi/zenity) for interactive selection
# - Allows: scan/search, connect (with password), save (persistent connection),
#   forget/delete saved connections, ignore/hide networks (persisted), toggle Wi-Fi power,
#   and view basic details
#
# Notes:
# - This script uses `nmcli` to interact with NetworkManager. Ensure `nmcli` is installed.
# - For password prompts it prefers a hidden input when supported (zenity or wofi --hide-text).
# - Ignored SSIDs are stored in: $XDG_CONFIG_HOME/KaguyaDots/swaync/ignored_wifi
#
# Author: KaguyaDots (adapted)
set -uo pipefail

# Basic helpers and config
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync"
IGNORED_FILE="$CONFIG_DIR/ignored_wifi"
mkdir -p "$CONFIG_DIR"
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/wifi.log"
echo "[$(date -Iseconds)] swaync-wifi-control started (TTY=$(tty 2>/dev/null || echo none), UI=${SWAYNC_UI:-auto})" >> "$LOG_FILE"

# UI selection: allow override via SWAYNC_UI; otherwise prefer wofi, fall back to rofi, then zenity
if [ -n "${SWAYNC_UI:-}" ]; then
  case "${SWAYNC_UI,,}" in
    wofi)
      if command -v wofi >/dev/null 2>&1; then
        UI="wofi"
      else
        echo "Warning: SWAYNC_UI='wofi' but wofi not found; will try auto-detection" >&2
      fi
      ;;
    rofi)
      if command -v rofi >/dev/null 2>&1; then
        UI="rofi"
      else
        echo "Warning: SWAYNC_UI='rofi' but rofi not found; will try auto-detection" >&2
      fi
      ;;
    zenity)
      if command -v zenity >/dev/null 2>&1; then
        UI="zenity"
      else
        echo "Warning: SWAYNC_UI='zenity' but zenity not found; will try auto-detection" >&2
      fi
      ;;
    *)
      echo "Warning: SWAYNC_UI is set to an unknown value '$SWAYNC_UI'; ignoring" >&2
      ;;
  esac
fi

# If no UI was forced (or forced UI unavailable), auto-detect
if [ -z "${UI:-}" ]; then
  if command -v wofi >/dev/null 2>&1; then
    UI="wofi"
  elif command -v rofi >/dev/null 2>&1; then
    UI="rofi"
  elif command -v zenity >/dev/null 2>&1; then
    UI="zenity"
  else
    echo "Error: No UI available (wofi/rofi/zenity). Please install wofi/rofi/zenity." >&2
    exit 1
  fi
fi

# Check nmcli
if ! command -v nmcli >/dev/null 2>&1; then
  if [ "$UI" = "zenity" ]; then
    zenity --error --text="nmcli (NetworkManager) not found. Please install NetworkManager."
  else
    notify-send "Wi‑Fi" "nmcli (NetworkManager) not found. Please install NetworkManager."
  fi
  exit 1
fi

# Notification helper (also logs to file)
notify() {
  local title="$1"; shift
  local msg="$*"
  notify-send -u normal "$title" "$msg"
  if [ -n "${LOG_FILE:-}" ]; then
    echo "[$(date -Iseconds)] NOTIFY: $title - $msg" >> "$LOG_FILE"
  fi
}

# Generic dmenu-style selector (uses wofi/rofi/zenity)
# --- Minimal helpers: active SSID, auto-save, stay-alive (keeps PC awake) ---
get_active_ssid() {
  nmcli -t -f IN-USE,SSID device wifi list 2>/dev/null | awk -F: '/^\*/{print $2; exit}' || echo ""
}

SAVED_FILE="$CONFIG_DIR/saved_wifi"
STAY_PID_FILE="$CONFIG_DIR/stay_alive.pid"

ensure_saved_file() { touch "$SAVED_FILE"; }

auto_save_current() {
  ensure_saved_file
  ssid="$(get_active_ssid)"
  [ -z "$ssid" ] && return
  if ! grep -Fxq -- "$ssid" "$SAVED_FILE" 2>/dev/null; then
    echo "$ssid" >> "$SAVED_FILE"
    notify "Wi‑Fi" "Saved: $ssid"
    [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] AUTO-SAVED: $ssid" >> "$LOG_FILE"
  fi
}

stay_alive_status() {
  if [ -f "$STAY_PID_FILE" ]; then
    pid="$(cat "$STAY_PID_FILE" 2>/dev/null || echo "")"
    [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1 && { echo "On"; return 0; } || rm -f "$STAY_PID_FILE"
  fi
  echo "Off"
}

toggle_stay_alive() {
  if [ "$(stay_alive_status)" = "On" ]; then
    pid="$(cat "$STAY_PID_FILE" 2>/dev/null || echo "")"
    kill "$pid" >/dev/null 2>&1 || true
    rm -f "$STAY_PID_FILE"
    notify "Stay-Alive" "Disabled"
    [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] STAY-ALIVE: disabled (pid=$pid)" >> "$LOG_FILE"
    return
  fi

  minutes="$(prompt_input "Stay alive minutes (default 60)")"
  minutes="${minutes:-60}"
  # Try systemd-inhibit if available; otherwise background sleep
  if command -v systemd-inhibit >/dev/null 2>&1; then
    (systemd-inhibit --what=sleep --why="Stay alive" bash -c "sleep $((minutes*60))") &
    pid=$!
  else
    (sleep $((minutes*60))) &
    pid=$!
  fi
  echo "$pid" > "$STAY_PID_FILE"
  notify "Stay-Alive" "Enabled for ${minutes} minutes"
  [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] STAY-ALIVE: enabled for ${minutes}m (pid=$pid)" >> "$LOG_FILE"
}

# Auto-save current active SSID whenever the control is invoked
auto_save_current

# Small startup notification (minimal)
state="$(get_wifi_power_status 2>/dev/null || echo unknown)"
active="$(get_active_ssid)"
notify "Wi‑Fi" "Power: ${state^} | Active: ${active:-None}"
[ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] STARTUP: power=$state active=${active:-None}" >> "$LOG_FILE"

dmenu_select() {
  local prompt="$1"; shift
  local entries=("$@")
  local input
  # If there are no entries, return empty
  if [ "${#entries[@]}" -eq 0 ]; then
    echo ""
    return 0
  fi

  case "$UI" in
    wofi)
      input=$(printf "%s\n" "${entries[@]}" | wofi --dmenu -i --prompt "$prompt")
      ;;
    rofi)
      input=$(printf "%s\n" "${entries[@]}" | rofi -dmenu -i -p "$prompt")
      ;;
    zenity)
      # zenity list expects columns; emulate a simple list
      input=$(printf "%s\n" "${entries[@]}" | awk '{print NR "|" $0}' | \
        zenity --list --title="$prompt" --column=idx --column=option --height=400 2>/dev/null | awk -F'|' '{print $2}')
      ;;
    *)
      input=""
      ;;
  esac

  printf "%s" "${input:-}"
}

# Prompt user for input (one-line). Preference order: zenity (entry) then wofi/rofi dmenu
prompt_input() {
  local prompt="$1"
  if command -v zenity >/dev/null 2>&1; then
    zenity --entry --title="$prompt" --text="$prompt" 2>/dev/null || echo ""
  elif [ "$UI" = "wofi" ]; then
    wofi --dmenu -i --prompt "$prompt"
  else
    rofi -dmenu -i -p "$prompt"
  fi
}

# Prompt for password (hidden input if possible)
prompt_password() {
  local prompt="$1"
  # zenity has a password dialog (hidden)
  if command -v zenity >/dev/null 2>&1; then
    zenity --password --title="$prompt" 2>/dev/null || echo ""
    return
  fi

  # wofi supports --hide-text in recent versions; try that then fallback to visible input
  if [ "$UI" = "wofi" ]; then
    if wofi --help 2>&1 | grep -q -- '--hide-text'; then
      wofi --dmenu --hide-text -i --prompt "$prompt"
      return
    fi
  fi

  # Fall back to plain dmenu (visible) if nothing else
  prompt_input "$prompt"
}

# Ignore list helpers
is_ignored() {
  local ssid="$1"
  [ -f "$IGNORED_FILE" ] && grep -Fxq -- "$ssid" "$IGNORED_FILE"
}

add_ignore() {
  local ssid="$1"
  touch "$IGNORED_FILE"
  if ! is_ignored "$ssid"; then
    echo "$ssid" >> "$IGNORED_FILE"
    notify "Wi‑Fi" "Ignored network: $ssid"
  else
    notify "Wi‑Fi" "Network already ignored: $ssid"
  fi
}

remove_ignore() {
  local ssid="$1"
  if [ -f "$IGNORED_FILE" ]; then
    grep -Fxv -- "$ssid" "$IGNORED_FILE" > "$IGNORED_FILE.tmp" || true
    mv "$IGNORED_FILE.tmp" "$IGNORED_FILE"
    [ ! -s "$IGNORED_FILE" ] && rm -f "$IGNORED_FILE"
    notify "Wi‑Fi" "Unignored network: $ssid"
  fi
}

# Get Wi‑Fi power status (enabled/disabled)
get_wifi_power_status() {
  nmcli radio wifi 2>/dev/null | tr -d '\r\n'
}

# Toggle power
toggle_wifi_power() {
  local st
  st=$(get_wifi_power_status)
  if [ "$st" = "enabled" ]; then
    nmcli radio wifi off >/dev/null 2>&1 && notify "Wi‑Fi" "Turned Wi‑Fi OFF"
  else
    nmcli radio wifi on >/dev/null 2>&1 && notify "Wi‑Fi" "Turned Wi‑Fi ON"
  fi
}

# Rescan for networks (doesn't block long)
rescan_networks() {
  nmcli device wifi rescan >/dev/null 2>&1
  sleep 1
}

# Fetch available networks (simple parse)
# Output lines: SSID | SIGNAL% | SECURITY | BSSID | INUSE
fetch_available_networks() {
  # Use terse colon-delimited output; some SSIDs can contain colons but it's rare.
  # Fields: IN-USE:SSID:SIGNAL:SECURITY:BSSID
  nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY,BSSID device wifi list --rescan yes 2>/dev/null | awk -F: '
    BEGIN { OFS=" | " }
    {
      inuse=$1; ssid=$2; signal=$3; sec=$4; bssid=$5;
      if (ssid=="") ssid="<hidden SSID>";
      if (inuse=="*") inuse="connected"; else inuse="";
      print ssid, signal"%", (sec=="" ? "NONE" : sec), (bssid=="" ? "N/A" : bssid), inuse
    }'
}

# Fetch saved Wi‑Fi connections (connection names mapped to SSID)
# Output lines: CONN_NAME | SSID
fetch_saved_connections() {
  # To find which saved connection corresponds to a specific SSID we use connection property 802-11-wireless.ssid
  nmcli -t -f NAME connection show 2>/dev/null | while IFS= read -r name; do
    ssid="$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null || echo "")"
    if [ -n "$ssid" ]; then
      echo "$name | $ssid"
    fi
  done
}

# Show details for a specific SSID/BSSID
show_network_details() {
  local ssid="$1"
  local bssid="$2"
  local details
  if [ -n "$bssid" ] && [ "$bssid" != "N/A" ]; then
    details="$(nmcli -f ALL device wifi list | grep -E -A10 "BSSID: $bssid" | sed -n '1,20p')"
  else
    details="$(nmcli -f ALL device wifi list | grep -E -A6 "SSID: $ssid" | sed -n '1,20p')"
  fi

  if [ -z "$details" ]; then
    details="No detailed info available"
  fi

  if [ "$UI" = "zenity" ]; then
    echo "$details" | zenity --text-info --title="Details: $ssid" --height=450 2>/dev/null
  else
    # display with a notification (short) and print to stdout/terminal for verbose info
    notify "Wi‑Fi: $ssid" "$(echo "$details" | sed -n '1,3p')"
    echo "$details" | sed -n '1,200p'
  fi
}

# Attempt to connect to a network (uses BSSID when available) — logs attempts/results
connect_to() {
  local ssid="$1"
  local bssid="$2"
  local password="$3" # may be empty for open networks

  if [ -n "${LOG_FILE:-}" ]; then
    echo "[$(date -Iseconds)] ATTEMPT connect ssid='$ssid' bssid='${bssid:-N/A}'" >> "$LOG_FILE"
  fi

  # Use bssid if provided
  if [ -n "$bssid" ] && [ "$bssid" != "N/A" ]; then
    if [ -n "$password" ]; then
      nmcli device wifi connect "$ssid" bssid "$bssid" password "$password"
    else
      nmcli device wifi connect "$ssid" bssid "$bssid"
    fi
  else
    if [ -n "$password" ]; then
      nmcli device wifi connect "$ssid" password "$password"
    else
      nmcli device wifi connect "$ssid"
    fi
  fi

  if [ $? -eq 0 ]; then
    notify "Wi‑Fi" "Connected to $ssid"
    [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] SUCCESS connect ssid='$ssid' bssid='${bssid:-N/A}'" >> "$LOG_FILE"
    return 0
  else
    notify "Wi‑Fi" "Failed to connect to $ssid"
    [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] FAIL connect ssid='$ssid' bssid='${bssid:-N/A}'" >> "$LOG_FILE"
    return 1
  fi
}

# Save (create) a connection profile for an SSID (if we have a password)
save_connection() {
  local ssid="$1"
  local bssid="$2"
  local password="$3"
  # Try connect (nmcli will create a connection profile when successful).
  if connect_to "$ssid" "$bssid" "$password"; then
    notify "Wi‑Fi" "Saved connection for $ssid"
    return 0
  else
    notify "Wi‑Fi" "Failed to save connection for $ssid"
    return 1
  fi
}

# Forget (delete) saved connections matching an SSID
forget_connection_by_ssid() {
  local ssid="$1"
  local matches
  matches="$(nmcli -t -f NAME connection show 2>/dev/null | while IFS= read -r name; do
    s="$(nmcli -g 802-11-wireless.ssid connection show "$name" 2>/dev/null || echo "")"
    if [ "$s" = "$ssid" ]; then
      echo "$name"
    fi
  done)"

  if [ -z "$matches" ]; then
    notify "Wi‑Fi" "No saved connections found for SSID: $ssid"
    return 1
  fi

  local deleted=0
  while IFS= read -r conn; do
    if [ -n "$conn" ]; then
      nmcli connection delete "$conn" >/dev/null 2>&1 && deleted=$((deleted+1))
    fi
  done <<< "$matches"

  notify "Wi‑Fi" "Deleted $deleted connection(s) for $ssid"
  return 0
}

# --- UI flows ---

# Show available networks and allow actions
show_available_flow() {
  rescan_networks

  local raw_entries
  IFS=$'\n' read -r -d '' -a raw_entries < <(fetch_available_networks && printf '\0')

  local choices=()
  for line in "${raw_entries[@]}"; do
    # line format: SSID | 42% | WPA2 | AA:BB:CC... | connected
    ssid="$(printf '%s' "$line" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
    signal="$(printf '%s' "$line" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"
    security="$(printf '%s' "$line" | awk -F'|' '{print $3}' | sed 's/^ *//; s/ *$//')"
    bssid="$(printf '%s' "$line" | awk -F'|' '{print $4}' | sed 's/^ *//; s/ *$//')"
    inuse="$(printf '%s' "$line" | awk -F'|' '{print $5}' | sed 's/^ *//; s/ *$//')"

    # Skip ignored SSIDs unless user wants to see them explicitly later
    if is_ignored "$ssid"; then
      continue
    fi

    local tag=""
    [ -n "$inuse" ] && tag="(Connected)"
    # Make display line: SSID | SIGNAL | SECURITY | BSSID | TAG
    choices+=("$ssid | $signal | $security | $bssid | $tag")
  done

  if [ "${#choices[@]}" -eq 0 ]; then
    notify "Wi‑Fi" "No available networks found (or all networks are hidden/ignored)."
    return
  fi

  local sel
  sel="$(dmenu_select 'Available networks (search to filter)' "${choices[@]}")"
  [ -z "$sel" ] && return

  # Parse selection
  local sel_ssid sel_signal sel_security sel_bssid sel_tag
  sel_ssid="$(printf '%s' "$sel" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
  sel_signal="$(printf '%s' "$sel" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"
  sel_security="$(printf '%s' "$sel" | awk -F'|' '{print $3}' | sed 's/^ *//; s/ *$//')"
  sel_bssid="$(printf '%s' "$sel" | awk -F'|' '{print $4}' | sed 's/^ *//; s/ *$//')"
  sel_tag="$(printf '%s' "$sel" | awk -F'|' '{print $5}' | sed 's/^ *//; s/ *$//')"

  # Action menu for selected network
  local actions=("Connect" "Save (Connect & Persist)" "Ignore / Hide" "Details" "Back")
  local act
  act="$(dmenu_select "Actions for: $sel_ssid" "${actions[@]}")"
  case "$act" in
    "Connect")
      local pw=""
      if [ "$sel_security" != "NONE" ] && [ "$sel_security" != "--" ]; then
        pw="$(prompt_password "Password for $sel_ssid")"
        [ -z "$pw" ] && notify "Wi‑Fi" "Cancelled connect to $sel_ssid" && return
      fi
      connect_to "$sel_ssid" "$sel_bssid" "$pw"
      ;;
    "Save (Connect & Persist)")
      local pw=""
      if [ "$sel_security" != "NONE" ] && [ "$sel_security" != "--" ]; then
        pw="$(prompt_password "Password for $sel_ssid (will be saved in NM) ")"
        [ -z "$pw" ] && notify "Wi‑Fi" "Cancelled save for $sel_ssid" && return
      fi
      save_connection "$sel_ssid" "$sel_bssid" "$pw"
      ;;
    "Ignore / Hide")
      add_ignore "$sel_ssid"
      ;;
    "Details")
      show_network_details "$sel_ssid" "$sel_bssid"
      ;;
    *) ;;
  esac
}

# Show saved connections and allow actions (connect/forget/unignore)
show_saved_flow() {
  local raw
  IFS=$'\n' read -r -d '' -a raw < <(fetch_saved_connections && printf '\0')
  local choices=()
  for line in "${raw[@]}"; do
    # line: CONN_NAME | SSID
    conn_name="$(printf '%s' "$line" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
    conn_ssid="$(printf '%s' "$line" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"
    choices+=("$conn_ssid | $conn_name")
  done

  if [ "${#choices[@]}" -eq 0 ]; then
    notify "Wi‑Fi" "No saved Wi‑Fi connections found."
    return
  fi

  local sel
  sel="$(dmenu_select "Saved networks" "${choices[@]}")"
  [ -z "$sel" ] && return

  local ssid conn
  ssid="$(printf '%s' "$sel" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
  conn="$(printf '%s' "$sel" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"

  local actions=("Connect" "Disconnect" "Forget (Delete)" "Unignore" "Details" "Back")
  local act
  act="$(dmenu_select "Actions for saved: $ssid" "${actions[@]}")"
  case "$act" in
    "Connect")
      nmcli connection up "$conn" >/dev/null 2>&1 && notify "Wi‑Fi" "Activated $ssid" || notify "Wi‑Fi" "Failed to activate $ssid"
      ;;
    "Disconnect")
      nmcli connection down "$conn" >/dev/null 2>&1 && notify "Wi‑Fi" "Disconnected $ssid" || notify "Wi‑Fi" "Failed to disconnect $ssid"
      ;;
    "Forget (Delete)")
      nmcli connection delete "$conn" >/dev/null 2>&1 && notify "Wi‑Fi" "Deleted saved connection: $conn" || notify "Wi‑Fi" "Failed to delete $conn"
      ;;
    "Unignore")
      remove_ignore "$ssid"
      ;;
    "Details")
      nmcli connection show "$conn" | sed -n '1,200p' | (if [ "$UI" = "zenity" ]; then zenity --text-info --title="Connection: $conn" --height=400 2>/dev/null; else echo "$(nmcli connection show "$conn" | sed -n '1,200p')"; fi)
      ;;
    *) ;;
  esac
}

# Manage ignored networks
manage_ignored_flow() {
  if [ ! -f "$IGNORED_FILE" ] || [ ! -s "$IGNORED_FILE" ]; then
    notify "Wi‑Fi" "No ignored networks"
    return
  fi
  mapfile -t ignored < "$IGNORED_FILE"
  local sel
  sel="$(dmenu_select "Ignored networks (select to unignore)" "${ignored[@]}")"
  [ -z "$sel" ] && return
  remove_ignore "$sel"
}

# The main menu loop
main_menu_loop() {
  while true; do
    title="Wi‑Fi"
    options=("Connected" "Saved" "Quit")
    choice="$(dmenu_select "$title" "${options[@]}")"
    [ -z "$choice" ] && return

    case "$choice" in
      "Connected")
        # List currently active Wi‑Fi connections (usually 0 or 1)
        mapfile -t conns < <(nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | awk -F: '$2 ~ /wifi|802-11-wireless/ {print $1 \" | \" $2}')
        if [ ${#conns[@]} -eq 0 ]; then
          notify "Wi‑Fi" "No active Wi‑Fi connections"
          continue
        fi
        sel="$(dmenu_select "Active connections" "${conns[@]}")"
        [ -z "$sel" ] && continue
        # Show brief details for selected connection
        ssid="$(printf '%s' "$sel" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
        dev="$(printf '%s' "$sel" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"
        notify "Wi‑Fi" "Connection: $ssid (device: $dev)"
        ;;
      "Saved")
        ensure_saved_file
        mapfile -t saved < "$SAVED_FILE"
        if [ ${#saved[@]} -eq 0 ]; then
          notify "Wi‑Fi" "No saved SSIDs"
          continue
        fi
        sel="$(dmenu_select \"Saved SSIDs\" \"${saved[@]}\")"
        [ -z "$sel" ] && continue
        # Allow quick forget (confirm)
        if prompt_confirm \"Forget $sel?\"; then
          grep -Fxv -- \"$sel\" \"$SAVED_FILE\" > \"$SAVED_FILE.tmp\" || true
          mv \"$SAVED_FILE.tmp\" \"$SAVED_FILE\"
          notify \"Wi‑Fi\" \"Forgot: $sel\"
          [ -n \"${LOG_FILE:-}\" ] && echo \"[$(date -Iseconds)] FORGOT: $sel\" >> \"$LOG_FILE\"
        else
          notify \"Wi‑Fi\" \"Kept: $sel\"
        fi
        ;;

      "Quit")
        return
        ;;
    esac
  done
}

# Non-interactive behavior: auto-save current SSID, notify, and exit
auto_save_current
state="$(get_wifi_power_status 2>/dev/null || echo unknown)"
active="$(get_active_ssid)"
if [ -n "$active" ]; then
  notify "Wi‑Fi" "Connected: $active"
else
  notify "Wi‑Fi" "No connected networks"
fi
exit 0
