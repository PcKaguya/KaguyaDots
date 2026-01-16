#!/usr/bin/env bash
# Simple Wi‑Fi status script for widgets
# Outputs one line suitable for a status widget:
# - "Wi‑Fi ?"    : nmcli not available
# - "Wi‑Fi Off"  : Wi‑Fi radio is disabled
# - "<SSID>"     : connected SSID (preferred)
# - "Wi‑Fi On"   : radio enabled but no active connection
#
# Designed to be used by e.g. eww widgets that read stdout.

set -euo pipefail

# Helper to safe-print
p() { printf '%s\n' "$*"; }

# If nmcli is not available, return an unknown state
if ! command -v nmcli >/dev/null 2>&1; then
  p "Wi‑Fi ?"
  exit 0
fi

# Check Wi‑Fi radio status (enabled/disabled)
radio_status=$(nmcli radio wifi 2>/dev/null || echo "disabled")
if [ "$radio_status" != "enabled" ]; then
  p "Wi‑Fi Off"
  exit 0
fi

# Try to find an active wifi connection via connections list (more robust than parsing SSID list)
active_conn=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2 ~ /wireless|wifi/ { print $1; exit }' || echo "")
if [ -n "$active_conn" ]; then
  ssid=$(nmcli -g 802-11-wireless.ssid connection show "$active_conn" 2>/dev/null || echo "")
  if [ -n "$ssid" ]; then
    p "$ssid"
    exit 0
  fi
fi

# Fallback: inspect the device wifi list for the entry marked '*' (in-use)
ssid=$(nmcli -t -f IN-USE,SSID device wifi list 2>/dev/null | awk -F: '/^\*/{print $2; exit}' || echo "")
if [ -n "$ssid" ]; then
  p "$ssid"
  exit 0
fi

# If nothing else, radio is on but no active SSID
p "Wi‑Fi On"
exit 0
