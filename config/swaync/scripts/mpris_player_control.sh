#!/bin/bash

# SwayNC MPRIS Player Control Script
# Displays current media player status and allows basic control.
# Prioritizes a single active player.

PLAYERCTL_CMD="/usr/bin/playerctl" # Adjust path if playerctl is elsewhere
SWAYNC_PLAYER_STATUS_FILE="/tmp/swaync_player_status.json"

# Check if playerctl is installed
if ! command -v "$PLAYERCTL_CMD" &>/dev/null;
then
    echo "{\"text\": \"No Playerctl\", \"tooltip\": \"Playerctl not found\", \"class\": \"disabled\"}"
    exit 1
fi

# Function to get all active player names
get_player_names() {
    "$PLAYERCTL_CMD" -l | tr '\n' ' '
}

# Function to get metadata for a given player
get_player_metadata() {
    local player_name="$1"
    local status=$(get_player_status "$player_name")
    local title="$($PLAYERCTL_CMD -p "$player_name" metadata title 2>/dev/null)"
    local artist="$($PLAYERCTL_CMD -p "$player_name" metadata artist 2>/dev/null)"
    local album="$($PLAYERCTL_CMD -p "$player_name" metadata album 2>/dev/null)"
    local art_url="$($PLAYERCTL_CMD -p "$player_name" metadata mpris:artUrl 2>/dev/null)"
    local position="$($PLAYERCTL_CMD -p "$player_name" position 2>/dev/null | xargs printf "%.0f")"
    local duration="$($PLAYERCTL_CMD -p "$player_name" metadata mpris:length 2>/dev/null | xargs printf "%.0f")"

    # Convert microseconds to seconds
    if [[ -n "$duration" ]]; then
        duration=$((duration / 1000000))
    fi

    # Format position and duration
    formatted_position=$(date -d@"${position:-0}" -u +%M:%S)
    formatted_duration=$(date -d@"${duration:-0}" -u +%M:%S)

    # Clean up empty values for display
    display_artist="${artist:-Unknown Artist}"
    display_title="${title:-Unknown Title}"
    display_album="${album:-Unknown Album}"

    tooltip="<b>$display_title</b>\n"
    tooltip+="<i>$display_artist</i> - $display_album\n"
    tooltip+="Status: $(echo "$status" | sed 's/.*/\u&/')\n" # Capitalize first letter
    if [[ "$duration" -gt 0 ]]; then
        tooltip+="Progress: $formatted_position / $formatted_duration"
    fi
    if [[ -n "$art_url" ]]; then
        # SwayNC doesn't directly support displaying art from URL in widget text,
        # but tooltip could potentially link it or a custom script could fetch it.
        # For simplicity, we just include the URL in the tooltip.
        tooltip+="\nArt: $art_url"
    fi

    echo "{\"player\": \"$player_name\", \"status\": \"$status\", \"title\": \"$title\", \"artist\": \"$artist\", \"album\": \"$album\", \"artUrl\": \"$art_url\", \"text\": \"󰐎 $display_artist - $display_title\", \"tooltip\": \"$tooltip\", \"class\": \"$status\"}"
}

# Function to get player status
get_player_status() {
    local player_name="$1"
    "$PLAYERCTL_CMD" -p "$player_name" status 2>/dev/null
}

# Main logic
main() {
    local players=$(get_player_names)
    local active_player_info=""

    # Prioritize playing player
    for p in $players;
    do
        if [[ "$(get_player_status "$p")" == "Playing" ]]; then
            active_player_info=$(get_player_metadata "$p")
            break
        fi
    done

    # If no playing player, get metadata for the first available player
    if [[ -z "$active_player_info" ]]; then
        for p in $players;
        do
            active_player_info=$(get_player_metadata "$p")
            break # Just take the first one
        done
    fi

    if [[ -n "$active_player_info" ]]; then
        # Cache player status for on-click actions
        echo "$active_player_info" | jq -c '.' > "$SWAYNC_PLAYER_STATUS_FILE"

        local status=$(echo "$active_player_info" | jq -r '.status')
        local title=$(echo "$active_player_info" | jq -r '.title')
        local artist=$(echo "$active_player_info" | jq -r '.artist')
        local text=""
        local tooltip=$(echo "$active_player_info" | jq -r '.tooltip')
        local class=$(echo "$active_player_info" | jq -r '.class')

        if [[ "$status" == "Playing" ]]; then
            text="󰏤 $artist - $title"
        elif [[ "$status" == "Paused" ]]; then
            text="󰐎 $artist - $title"
        else
            text="󰐎 $artist - $title" # Default to paused icon if status is not Playing/Paused
        fi

        echo "{\"text\": \"$text\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"
    else
        # No active player
        rm -f "$SWAYNC_PLAYER_STATUS_FILE" # Clean up old status
        echo "{\"text\": \"\", \"tooltip\": \"No media playing\", \"class\": \"disabled\"}"
    fi
}

# Handle on-click actions
if [[ "$1" == "--action" ]]; then
    if [[ ! -f "$SWAYNC_PLAYER_STATUS_FILE" ]]; then
        send_notification "Media Player" "No media playing to control." "low"
        exit 0
    fi

    local player_name=$(jq -r '.player' "$SWAYNC_PLAYER_STATUS_FILE")
    local current_status=$(jq -r '.status' "$SWAYNC_PLAYER_STATUS_FILE")

    if [[ "$2" == "play-pause" ]]; then
        "$PLAYERCTL_CMD" -p "$player_name" play-pause &>/dev/null
        if [[ "$current_status" == "Playing" ]]; then
            send_notification "Media Player" "Paused $player_name." "low"
        else
            send_notification "Media Player" "Playing $player_name." "low"
        fi
    elif [[ "$2" == "next" ]]; then
        "$PLAYERCTL_CMD" -p "$player_name" next &>/dev/null
        send_notification "Media Player" "Next track on $player_name." "low"
    elif [[ "$2" == "previous" ]]; then
        "$PLAYERCTL_CMD" -p "$player_name" previous &>/dev/null
        send_notification "Media Player" "Previous track on $player_name." "low"
    fi
    exit 0
fi

main
