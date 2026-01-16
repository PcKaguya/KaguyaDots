#!/usr/bin/env bash
#
# swaync-bluetooth-control.sh
#
# Wofi-based Bluetooth manager for SwayNC
# - Uses wofi for interactive menus (falls back to rofi/zenity)
# - Allows: toggle bluetooth power, scan/search, pair, connect, disconnect,
#   trust/untrust (save), remove (forget), ignore/hide devices
# - Ignored devices are stored in: $XDG_CONFIG_HOME/KaguyaDots/swaync/ignored_bt
#
# Notes:
# - Requires `bluetoothctl` (BlueZ) to manage Bluetooth devices.
# - For pairing that requires PIN/confirmation, a device-side confirmation may be required.
set -uo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/KaguyaDots/swaync"
IGNORED_BT_FILE="$CONFIG_DIR/ignored_bt"
mkdir -p "$CONFIG_DIR"
touch "$IGNORED_BT_FILE" 2>/dev/null || true

# Determine preferred UI (allow override with SWAYNC_UI env var)
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

# Check bluetoothctl
if ! command -v bluetoothctl >/dev/null 2>&1; then
  if [ "$UI" = "zenity" ]; then
    zenity --error --text="bluetoothctl (BlueZ) not found. Please install BlueZ."
  else
    notify-send "Bluetooth" "bluetoothctl (BlueZ) not found. Please install BlueZ."
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

# Logging and quick startup status
LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/bt.log"
echo "[$(date -Iseconds)] swaync-bluetooth-control started (TTY=$(tty 2>/dev/null || echo none), UI=${SWAYNC_UI:-auto})" >> "$LOG_FILE"

log() {
  printf "%s %s\n" "$(date '+%F %T')" "$*" >> "$LOG_FILE"
}

# Quick startup notification & log (helps when UI is invisible/transparent)
{
  bt_power="$(bluetoothctl show 2>/dev/null | awk -F': ' '/Powered/ {print $2}' || echo unknown)"
  connected="$(bluetoothctl devices 2>/dev/null | awk '{$1=\"\"; print substr($0,2)}' | tr '\n' ',' | sed 's/,$//' || echo none)"
  notify "Bluetooth" "Power: ${bt_power^} | Connected: ${connected:-none}"
  [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] STARTUP: power=${bt_power} connected=${connected:-none}" >> "$LOG_FILE"
} >/dev/null 2>&1 || true

# Generic selector (dmenu-style). Returns the selected entry.
dmenu_select() {
  local prompt="$1"
  shift
  local entries=("$@")
  [ "${#entries[@]}" -eq 0 ] && echo "" && return 0

  if [ "$UI" = "wofi" ]; then
    printf "%s\n" "${entries[@]}" | wofi --dmenu -i --prompt "$prompt"
  elif [ "$UI" = "rofi" ]; then
    printf "%s\n" "${entries[@]}" | rofi -dmenu -i -p "$prompt"
  else
    # zenity list as fallback
    printf "%s\n" "${entries[@]}" | nl -w1 -s'|' | \
      awk -F'|' '{print $2 "#" NR}' | \
      zenity --list --title="$prompt" --column=entry --height=400 2>/dev/null | \
      awk -F'#' '{print $1}'
  fi
}

# Simple input prompt (single line). Use zenity if available for nicer input.
prompt_input() {
  local prompt="$1"
  if [ "$UI" = "zenity" ]; then
    zenity --entry --title="$prompt" --text="$prompt" 2>/dev/null || echo ""
  elif [ "$UI" = "wofi" ]; then
    wofi --dmenu -i --prompt "$prompt"
  else
    rofi -dmenu -i -p "$prompt"
  fi
}

# Yes/No confirmation
prompt_confirm() {
  local prompt="$1"
  if [ "$UI" = "zenity" ]; then
    if zenity --question --text="$prompt" 2>/dev/null; then
      return 0
    else
      return 1
    fi
  else
    local ans
    ans="$(dmenu_select "$prompt" "Yes" "No")"
    [ "$ans" = "Yes" ]
  fi
}

# Ignore list helpers
is_ignored() {
  local mac_or_name="$1"
  [ -f "$IGNORED_BT_FILE" ] && grep -Fxq -- "$mac_or_name" "$IGNORED_BT_FILE"
}
add_ignore() {
  local mac_or_name="$1"
  touch "$IGNORED_BT_FILE"
  if ! is_ignored "$mac_or_name"; then
    echo "$mac_or_name" >> "$IGNORED_BT_FILE"
    notify "Bluetooth" "Ignored: $mac_or_name"
  else
    notify "Bluetooth" "Already ignored: $mac_or_name"
  fi
}
remove_ignore() {
  local mac_or_name="$1"
  if [ -f "$IGNORED_BT_FILE" ]; then
    grep -Fxv -- "$mac_or_name" "$IGNORED_BT_FILE" > "$IGNORED_BT_FILE.tmp" || true
    mv "$IGNORED_BT_FILE.tmp" "$IGNORED_BT_FILE"
    [ ! -s "$IGNORED_BT_FILE" ] && rm -f "$IGNORED_BT_FILE"
    notify "Bluetooth" "Unignored: $mac_or_name"
  fi
}

# Bluetooth power state
get_power() {
  bluetoothctl show 2>/dev/null | awk -F': ' '/Powered:/ {print $2}' | tr -d '\r\n'
}
toggle_power() {
  local p
  p=$(get_power)
  if [ "$p" = "yes" ]; then
    bluetoothctl power off >/dev/null 2>&1 && notify "Bluetooth" "Powered OFF"
  else
    bluetoothctl power on >/dev/null 2>&1 && notify "Bluetooth" "Powered ON"
  fi
}

# Scanning
scan_for_devices() {
  # Start a quick scan (on then off after a short wait) to populate devices
  bluetoothctl scan on >/dev/null 2>&1
  sleep 4
  bluetoothctl scan off >/dev/null 2>&1
}

# Fetch devices (discovered). Returns lines "MAC | NAME | connected/paired/trusted"
fetch_devices() {
  # Output each device as: MAC | NAME | Connected?|Paired?|Trusted?
  # Use 'bluetoothctl devices' to list
  bluetoothctl devices | while read -r _ mac name; do
    [ -z "$mac" ] && continue
    name="${name:-<unknown>}"
    info="$(bluetoothctl info "$mac" 2>/dev/null || true)"
    connected="no"; paired="no"; trusted="no"
    echo "$info" | grep -q "Connected: yes" && connected="yes"
    echo "$info" | grep -q "Paired: yes" && paired="yes"
    echo "$info" | grep -q "Trusted: yes" && trusted="yes"
    printf "%s | %s | %s | %s | %s\n" "$mac" "$name" "$connected" "$paired" "$trusted"
  done
}

# Fetch paired devices (only)
fetch_paired_devices() {
  bluetoothctl paired-devices | while read -r _ mac name; do
    [ -z "$mac" ] && continue
    name="${name:-<unknown>}"
    info="$(bluetoothctl info "$mac" 2>/dev/null || true)"
    connected="no"; trusted="no"
    echo "$info" | grep -q "Connected: yes" && connected="yes"
    echo "$info" | grep -q "Trusted: yes" && trusted="yes"
    printf "%s | %s | %s | %s\n" "$mac" "$name" "$connected" "$trusted"
  done
}

# Show details (bluetoothctl info)
show_device_details() {
  local mac="$1"
  local name="$2"
  info="$(bluetoothctl info "$mac" 2>/dev/null || echo 'No info available')"
  if [ "$UI" = "zenity" ]; then
    echo "$info" | zenity --text-info --title="Details: $name ($mac)" --height=400 2>/dev/null
  else
    notify "Bluetooth: $name" "$(echo "$info" | sed -n '1,3p')"
    echo "$info"
  fi
}

# Actions
pair_device() {
  local mac="$1"
  local name="$2"
  notify "Bluetooth" "Pairing with $name ($mac). Confirm on the device if necessary."
  bluetoothctl <<EOF >/dev/null 2>&1
agent on
default-agent
pair $mac
EOF
  sleep 1
  if bluetoothctl info "$mac" | grep -q "Paired: yes"; then
    notify "Bluetooth" "Paired $name ($mac)"
  else
    notify "Bluetooth" "Failed to pair $name ($mac)" "critical"
  fi
}

connect_device() {
  local mac="$1"
  local name="$2"
  bluetoothctl connect "$mac" >/dev/null 2>&1
  sleep 1
  if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
    notify "Bluetooth" "Connected to $name"
  else
    notify "Bluetooth" "Failed to connect $name" "critical"
  fi
}

disconnect_device() {
  local mac="$1"
  local name="$2"
  bluetoothctl disconnect "$mac" >/dev/null 2>&1
  sleep 1
  notify "Bluetooth" "Disconnected $name"
}

trust_device() {
  local mac="$1"; local name="$2"
  bluetoothctl trust "$mac" >/dev/null 2>&1
  notify "Bluetooth" "Trusted $name"
}

untrust_device() {
  local mac="$1"; local name="$2"
  bluetoothctl untrust "$mac" >/dev/null 2>&1
  notify "Bluetooth" "Untrusted $name"
}

remove_device() {
  local mac="$1"; local name="$2"
  if prompt_confirm "Remove (unpair) $name ($mac)?"; then
    bluetoothctl remove "$mac" >/dev/null 2>&1
    notify "Bluetooth" "Removed $name"
  fi
}

# UI flows
show_discovered_flow() {
  scan_for_devices
  IFS=$'\n' read -r -d '' -a raw < <(fetch_devices && printf '\0')
  local choices=()
  for line in "${raw[@]}"; do
    mac="$(printf "%s" "$line" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
    name="$(printf "%s" "$line" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"
    connected="$(printf "%s" "$line" | awk -F'|' '{print $3}' | sed 's/^ *//; s/ *$//')"
    paired="$(printf "%s" "$line" | awk -F'|' '{print $4}' | sed 's/^ *//; s/ *$//')"
    trusted="$(printf "%s" "$line" | awk -F'|' '{print $5}' | sed 's/^ *//; s/ *$//')"

    # Skip ignored
    if is_ignored "$mac" || is_ignored "$name"; then
      continue
    fi

    local tag=""
    [ "$connected" = "yes" ] && tag+="(connected) "
    [ "$paired" = "yes" ] && tag+="(paired) "
    [ "$trusted" = "yes" ] && tag+="(trusted)"
    choices+=("$mac | $name | $tag")
  done

  if [ "${#choices[@]}" -eq 0 ]; then
    notify "Bluetooth" "No devices found (or all devices are ignored)."
    return
  fi

  local sel
  sel="$(dmenu_select "Discovered devices (search/filter)" "${choices[@]}")"
  [ -z "$sel" ] && return

  sel_mac="$(printf '%s' "$sel" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
  sel_name="$(printf '%s' "$sel" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"

  # fetch current state
  info="$(bluetoothctl info "$sel_mac" 2>/dev/null || true)"
  connected="no"; paired="no"; trusted="no"
  echo "$info" | grep -q "Connected: yes" && connected="yes"
  echo "$info" | grep -q "Paired: yes" && paired="yes"
  echo "$info" | grep -q "Trusted: yes" && trusted="yes"

  local actions=()
  if [ "$paired" = "no" ]; then
    actions+=("Pair")
  fi
  if [ "$connected" = "no" ]; then
    actions+=("Connect")
  else
    actions+=("Disconnect")
  fi
  if [ "$trusted" = "no" ]; then
    actions+=("Trust (Save)")
  else
    actions+=("Untrust")
  fi
  actions+=("Ignore/Hide")
  actions+=("Details")
  actions+=("Back")

  local act
  act="$(dmenu_select "Actions: $sel_name" "${actions[@]}")"
  case "$act" in
    "Pair")
      pair_device "$sel_mac" "$sel_name"
      ;;
    "Connect")
      connect_device "$sel_mac" "$sel_name"
      ;;
    "Disconnect")
      disconnect_device "$sel_mac" "$sel_name"
      ;;
    "Trust (Save)")
      trust_device "$sel_mac" "$sel_name"
      ;;
    "Untrust")
      untrust_device "$sel_mac" "$sel_name"
      ;;
    "Ignore/Hide")
      add_ignore "$sel_mac"
      add_ignore "$sel_name"
      ;;
    "Details")
      show_device_details "$sel_mac" "$sel_name"
      ;;
    *) ;;
  esac
}

show_paired_flow() {
  IFS=$'\n' read -r -d '' -a raw < <(fetch_paired_devices && printf '\0')
  local choices=()
  for line in "${raw[@]}"; do
    mac="$(printf "%s" "$line" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
    name="$(printf "%s" "$line" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"
    connected="$(printf "%s" "$line" | awk -F'|' '{print $3}' | sed 's/^ *//; s/ *$//')"
    trusted="$(printf "%s" "$line" | awk -F'|' '{print $4}' | sed 's/^ *//; s/ *$//')"

    # Skip ignored
    if is_ignored "$mac" || is_ignored "$name"; then
      continue
    fi

    local tag=""
    [ "$connected" = "yes" ] && tag+="(connected) "
    [ "$trusted" = "yes" ] && tag+="(trusted)"
    choices+=("$mac | $name | $tag")
  done

  if [ "${#choices[@]}" -eq 0 ]; then
    notify "Bluetooth" "No paired devices found."
    return
  fi

  local sel
  sel="$(dmenu_select "Paired devices" "${choices[@]}")"
  [ -z "$sel" ] && return

  sel_mac="$(printf '%s' "$sel" | awk -F'|' '{print $1}' | sed 's/^ *//; s/ *$//')"
  sel_name="$(printf '%s' "$sel" | awk -F'|' '{print $2}' | sed 's/^ *//; s/ *$//')"

  info="$(bluetoothctl info "$sel_mac" 2>/dev/null || true)"
  connected="no"; trusted="no"
  echo "$info" | grep -q "Connected: yes" && connected="yes"
  echo "$info" | grep -q "Trusted: yes" && trusted="yes"

  local actions=("Connect" "Disconnect" "Trust" "Untrust" "Forget/Remove" "Ignore/Hide" "Details" "Back")
  local act
  act="$(dmenu_select "Actions: $sel_name" "${actions[@]}")"
  case "$act" in
    "Connect")
      connect_device "$sel_mac" "$sel_name"
      ;;
    "Disconnect")
      disconnect_device "$sel_mac" "$sel_name"
      ;;
    "Trust")
      trust_device "$sel_mac" "$sel_name"
      ;;
    "Untrust")
      untrust_device "$sel_mac" "$sel_name"
      ;;
    "Forget/Remove")
      remove_device "$sel_mac" "$sel_name"
      ;;
    "Ignore/Hide")
      add_ignore "$sel_mac"
      add_ignore "$sel_name"
      ;;
    "Details")
      show_device_details "$sel_mac" "$sel_name"
      ;;
    *) ;;
  esac
}

manage_ignored_flow() {
  if [ ! -f "$IGNORED_BT_FILE" ] || [ ! -s "$IGNORED_BT_FILE" ]; then
    notify "Bluetooth" "No ignored devices"
    return
  fi
  mapfile -t ignored < "$IGNORED_BT_FILE"
  local sel
  sel="$(dmenu_select "Ignored devices (select to unignore)" "${ignored[@]}")"
  [ -z "$sel" ] && return
  remove_ignore "$sel"
}

# Simplified behavior (auto-save and minimal summary)
# - Auto-save currently-connected Bluetooth devices to a saved list
# - Notify a concise summary of currently connected devices
# - Minimal interaction (no large menus) as requested
SAVED_BT="$CONFIG_DIR/saved_bt"
touch "$SAVED_BT" 2>/dev/null || true

auto_save_connected_bt() {
  # Iterate discovered devices and save the ones that are connected
  while read -r _ mac name; do
    info="$(bluetoothctl info "$mac" 2>/dev/null || true)"
    if echo "$info" | grep -q "Connected: yes"; then
      entry="$mac|$name"
      if ! grep -Fxq -- "$entry" "$SAVED_BT" 2>/dev/null; then
        echo "$entry" >> "$SAVED_BT"
        [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] AUTO-SAVED BT: $entry" >> "$LOG_FILE"
      fi
    fi
  done < <(bluetoothctl devices 2>/dev/null)
}

list_connected_bt() {
  # Returns newline-separated lines of the form: Name (MAC)
  bluetoothctl devices 2>/dev/null | while read -r _ mac name; do
    if bluetoothctl info "$mac" 2>/dev/null | grep -q "Connected: yes"; then
      printf "%s (%s)\n" "$name" "$mac"
    fi
  done
}

# Run auto-save and notify summary
auto_save_connected_bt
connected_list="$(list_connected_bt)"

if [ -z "$connected_list" ]; then
  notify "Bluetooth" "No connected devices"
  [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] NO_BT_CONNECTED" >> "$LOG_FILE"
else
  # Shorten the summary for notification; preserve newlines for readability
  notify "Bluetooth" "Connected:\n$connected_list"
  [ -n "${LOG_FILE:-}" ] && echo "[$(date -Iseconds)] CONNECTED: $(printf '%s; ' $(echo \"$connected_list\"))" >> "$LOG_FILE"
fi

exit 0
