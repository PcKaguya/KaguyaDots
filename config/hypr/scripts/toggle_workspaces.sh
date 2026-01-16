#!/bin/bash

WAYBAR_CONFIG="$HOME/.config/waybar/config"

current_config=$(cat "$WAYBAR_CONFIG")

if grep -q '"hyprland/workspaces#numbers"' "$WAYBAR_CONFIG"; then
    # Currently using numbers, switch to icons
    new_config=$(echo "$current_config" | sed 's/"hyprland\/workspaces#numbers"/"hyprland\/workspaces#icons"/g')
    echo "$new_config" > "$WAYBAR_CONFIG"
    echo "Switched to workspace icons."
else
    # Currently using icons, switch to numbers
    new_config=$(echo "$current_config" | sed 's/"hyprland\/workspaces#icons"/"hyprland\/workspaces#numbers"/g')
    echo "$new_config" > "$WAYBAR_CONFIG"
    echo "Switched to workspace numbers."
fi

# Reload Waybar
pkill -SIGUSR2 waybar
