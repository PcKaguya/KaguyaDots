#!/bin/bash
# Script to reconnect to a paired and trusted bluetooth device.

# Wait a few seconds to let bluetooth services initialize
sleep 5

# Find trusted, paired devices and attempt to connect
bluetoothctl devices Paired | cut -d ' ' -f 2 | while read -r uuid; do
    if bluetoothctl info "$uuid" | grep -q "Connected: no"; then
        bluetoothctl connect "$uuid"
        # If connection is successful, exit the loop
        if [ $? -eq 0 ]; then
            echo "Connected to $uuid" > /tmp/bluetooth-reconnect.log
            exit 0
        fi
    fi
done
