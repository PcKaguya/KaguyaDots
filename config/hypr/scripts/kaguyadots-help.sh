#!/bin/bash

PROGRAM="$HOME/.local/bin/Kaguya-Settings"
PID=$(pgrep -x "Kaguya-Settings")

if [ -n "$PID" ]; then
  kill "$PID"
else
  setsid "$PROGRAM" "$1" > /dev/null 2>&1 &
fi
