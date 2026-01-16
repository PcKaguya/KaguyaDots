#!/usr/bin/env bash
# EWW Bluetooth status script — show connected device names when available
# Outputs:
# - "BT Off" when Bluetooth power is off
# - "BT On" when power is on but no devices connected
# - "Name1, Name2" when one or more devices are connected
if ! command -v bluetoothctl >/dev/null 2>&1; then
  echo "BT ?" && exit 0
fi

# If Bluetooth is powered off, show BT Off
if ! bluetoothctl show 2>/dev/null | awk -F': ' '/Powered/ {print $2}' | grep -q '^yes$'; then
  echo "BT Off"
  exit 0
fi

# Collect connected device names
connected=()
while IFS= read -r line; do
  mac=$(printf '%s' "$line" | awk '{print $2}')
  name=$(printf '%s' "$line" | cut -d' ' -f3-)
  if bluetoothctl info "$mac" 2>/dev/null | awk -F': ' '/Connected/ {print $2}' | grep -q '^yes$'; then
    connected+=("$name")
  fi
done < <(bluetoothctl devices 2>/dev/null)

if [ ${#connected[@]} -gt 0 ]; then
  IFS=', '; echo "${connected[*]}"
else
  echo "BT On"
fi
