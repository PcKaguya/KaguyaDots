#!/usr/bin/env bash

# Volume Control Script for Wayland (PulseAudio)

# Set the sink (usually @DEFAULT_SINK@ or a specific sink name)
SINK="@DEFAULT_SINK@"

# Function to get current volume and mute status
get_volume() {
    # Get current volume
    VOLUME=$(pactl get-sink-volume "$SINK" | grep -Po '[0-9]{1,3}(?%)' | head -n 1)
    # Get mute status
    MUTE_STATUS=$(pactl get-sink-mute "$SINK" | awk '{print $2}')
}

# Function to send a notification
send_notification() {
    get_volume
    if [ "$MUTE_STATUS" = "yes" ]; then
        notify-send -a "Volume" -u low -i audio-volume-muted -h string:x-canonical-private-synchronous:volume-notification "Muted"
    else
        notify-send -a "Volume" -u low -i audio-volume-high -h string:x-canonical-private-synchronous:volume-notification -h int:value:"$VOLUME" "Volume: $VOLUME%"
    fi
}

# Function to change volume
volume_change() {
    DIRECTION=$1
    if [ "$DIRECTION" = "up" ]; then
        pactl set-sink-volume "$SINK" +2%
    elif [ "$DIRECTION" = "down" ]; then
        pactl set-sink-volume "$SINK" -2%
    fi
    send_notification
}

# Function to toggle mute
volume_mute() {
    pactl set-sink-mute "$SINK" toggle
    send_notification
}

# Main script logic
case "$1" in
    up|--inc) # Add --inc as an alias for up
        volume_change "up"
        ;;
    down|--dec) # Add --dec as an alias for down
        volume_change "down"
        ;;
    mute|--toggle) # Add --toggle as an alias for mute
        volume_mute
        ;;
    *)
        echo "Usage: $0 {up|down|mute|--inc|--dec|--toggle}"
        exit 1
        ;;
esac