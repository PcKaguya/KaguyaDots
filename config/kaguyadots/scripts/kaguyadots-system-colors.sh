#!/bin/bash

# Waypaper Color Update Script
# Updates system-wide colors based on wallpaper
# Respects KaguyaDots theme mode (dynamic/static)

CONFIG="$HOME/.config/waypaper/config.ini"
COLOR_CACHE="$HOME/.cache/wal/colors.json"
KAGUYADOTS_CONFIG="$HOME/.config/kaguyadots/kaguyadots.toml"
KAGUYADOTS_UPDATE_SCRIPT="$HOME/.config/kaguyadots/scripts/update_kaguyadots_colors.sh"

# Check theme mode from kaguyadots.toml
get_theme_mode() {
  if [ -f "$KAGUYADOTS_CONFIG" ]; then
      local mode=$(grep "^mode" "$KAGUYADOTS_CONFIG" | cut -d '=' -f2 | tr -d ' "')
      echo "$mode"
  else
    echo "dynamic" # Default to dynamic if config not found
  fi
}

THEME_MODE=$(get_theme_mode)

# If theme is static, exit without updating
if [ "$THEME_MODE" = "static" ]; then
  echo "Theme mode is set to static. Skipping color update."
  notify-send "Wallpaper Changed" "Theme mode: Static (colors not updated)" -u low
  exit 0
fi

# Extract wallpaper path
WP_PATH=$(grep '^wallpaper' "$CONFIG" | cut -d '=' -f2 | tr -d ' ')
WP_PATH="${WP_PATH/#\~/$HOME}"

if [ ! -f "$WP_PATH" ]; then
  echo "Error: Wallpaper not found at $WP_PATH"
  exit 1
fi

echo "Wallpaper changed to: $WP_PATH"
echo "Theme mode: $THEME_MODE - Generating color scheme..."

# Ensure cache directory exists
mkdir -p "$HOME/.cache/wal"

# Run pywal
if ! wal -n -i "$WP_PATH" -q -t -s 2>&1 | grep -v "Remote control is disabled" | tee /tmp/wal_error.log; then
  if grep -qv "Remote control is disabled" /tmp/wal_error.log 2>/dev/null; then
    echo "Error: wal command failed. Check /tmp/wal_error.log for details"
    cat /tmp/wal_error.log
    exit 1
  fi
fi

# Wait for wal to finish and verify colors.json exists
max_attempts=10
attempt=0
while [ ! -f "$COLOR_CACHE" ] && [ $attempt -lt $max_attempts ]; do
  sleep 0.2
  attempt=$((attempt + 1))
done

if [ ! -f "$COLOR_CACHE" ]; then
  echo "Error: Pywal failed to generate colors.json"
  echo "Last wal output:"
  cat /tmp/wal_error.log 2>/dev/null
  exit 1
fi

# Verify colors.json is valid JSON
if ! jq -e '.special.background' "$COLOR_CACHE" >/dev/null 2>&1; then
  echo "Error: colors.json is invalid or incomplete"
  echo "Content:"
  cat "$COLOR_CACHE"
  exit 1
fi

echo "✓ Color scheme generated successfully"
sleep 0.3

# Run centralized color update script
echo ""
echo "═══════════════════════════════════════════════════════════"
echo "Updating KaguyaDots Theme..."
echo "═══════════════════════════════════════════════════════════"

if [ -f "$KAGUYADOTS_UPDATE_SCRIPT" ]; then
  if bash "$KAGUYADOTS_UPDATE_SCRIPT"; then
    notify-send "✓ KaguyaDots Theme Updated" "All components synced successfully!" -u normal
    exit 0
  else
    notify-send "✗ Theme Update Failed" "Check logs for details" -u critical
    exit 1
  fi
else
  echo "Error: KaguyaDots update script not found at $KAGUYADOTS_UPDATE_SCRIPT"
  echo "Expected location: $KAGUYADOTS_UPDATE_SCRIPT"
  notify-send "✗ Theme Script Missing" "Cannot find update_kaguyadots_colors.sh" -u critical
  exit 1
fi
