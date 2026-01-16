#!/bin/bash

PROGRAM="$HOME/.local/bin/KaguyaDots-Settings"
PID=$(pgrep -x "KaguyaDots-Settings")

if [ -n "$PID" ]; then
  kill "$PID"
else
  setsid "$PROGRAM" "$1" > /dev/null 2>&1 &
fi
