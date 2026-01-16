#!/usr/bin/env bash
#
# stay_alive.sh
#
# Core "Stay Alive" utility to inhibit system sleep for a given duration.
# Usage:
#   stay_alive.sh on [DURATION] [--force]   # start inhibitor for DURATION (default: 60m)
#   stay_alive.sh off                       # stop inhibitor
#   stay_alive.sh status                    # print 'on <remaining>' or 'off'
#   stay_alive.sh toggle [DURATION]         # toggle: enable (with duration) or disable if running
#
# DURATION formats accepted:
#   - integer (no suffix) => minutes (e.g., 60 -> 60 minutes)
#   - <n>s / <n>m / <n>h / <n>d (seconds, minutes, hours, days)
#   - forever or 0 => indefinite
#
# Behaviour:
#   - Tries to use `systemd-inhibit` when available (preferred).
#   - Falls back to plain `sleep` (may NOT prevent systemd sleep properly).
#   - Persists PID and expiry in: ${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync/
#
set -euo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/KaguyaDots/swaync"
mkdir -p "$CACHE_DIR"

PIDFILE="$CACHE_DIR/stay_alive.pid"
EXPIREFILE="$CACHE_DIR/stay_alive.expire"
LOGFILE="$CACHE_DIR/stay_alive.log"

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOGFILE"
}

usage() {
  cat <<EOF
Usage:
  $0 on [DURATION] [--force]   Start inhibit (default duration: 60m). Duration examples: 30, 15m, 2h, 1d, 0/forever
  $0 off                       Stop inhibit
  $0 status|show               Show status (on/off and remaining time)
  $0 toggle [DURATION]         Toggle state (enable with DURATION if currently off)
EOF
}

# Parse a duration string into seconds.
# Return seconds on stdout, exit non-zero on parse error.
parse_duration_to_seconds() {
  local s="$1"
  if [ -z "$s" ]; then
    echo 3600   # default 60m
    return 0
  fi
  if [[ "$s" =~ ^([0-9]+)$ ]]; then
    # plain number => minutes
    echo $((BASH_REMATCH[1] * 60))
    return 0
  fi
  if [[ "$s" =~ ^([0-9]+)s$ ]]; then
    echo "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$s" =~ ^([0-9]+)m$ ]]; then
    echo $((BASH_REMATCH[1] * 60))
    return 0
  fi
  if [[ "$s" =~ ^([0-9]+)h$ ]]; then
    echo $((BASH_REMATCH[1] * 3600))
    return 0
  fi
  if [[ "$s" =~ ^([0-9]+)d$ ]]; then
    echo $((BASH_REMATCH[1] * 86400))
    return 0
  fi
  if [[ "$s" == "0" || "$s" == "forever" ]]; then
    echo 0
    return 0
  fi
  return 1
}

# Format seconds into human readable string
format_seconds() {
  local secs="$1"
  if [ "$secs" = "forever" ]; then
    printf 'forever'
    return
  fi
  if ! [[ "$secs" =~ ^[0-9]+$ ]]; then
    printf '%s' "$secs"
    return
  fi
  if [ "$secs" -le 0 ]; then
    printf '0s'
    return
  fi
  local days=$((secs/86400)); secs=$((secs%86400))
  local hours=$((secs/3600)); secs=$((secs%3600))
  local mins=$((secs/60)); secs=$((secs%60))
  local out=""
  [ "$days" -gt 0 ] && out+="${days}d "
  [ "$hours" -gt 0 ] && out+="${hours}h "
  [ "$mins" -gt 0 ] && out+="${mins}m "
  [ "$secs" -gt 0 ] && out+="${secs}s"
  printf '%s' "${out%% }"
}

# Returns 0 if inhibit is currently active (and pid file is valid), else 1.
is_on() {
  if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    else
      rm -f "$PIDFILE" "$EXPIREFILE" 2>/dev/null || true
      return 1
    fi
  fi
  return 1
}

remaining_seconds() {
  if [ ! -f "$EXPIREFILE" ]; then
    printf '0'
    return
  fi
  expiry=$(cat "$EXPIREFILE" 2>/dev/null || echo "")
  if [ -z "$expiry" ]; then
    printf '0'
    return
  fi
  if [ "$expiry" = "0" ]; then
    printf 'forever'
    return
  fi
  now=$(date +%s)
  if [ "$expiry" -le "$now" ]; then
    printf '0'
  else
    printf '%s' $((expiry - now))
  fi
}

_notify() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$@"
  fi
}

start_inhibitor() {
  local seconds="$1"   # 0 => forever
  # If an inhibitor already running, do nothing (caller may choose --force to override)
  if is_on; then
    log "start_inhibitor() requested but already active"
    return 1
  fi

  local pid
  if command -v systemd-inhibit >/dev/null 2>&1; then
    if [ "$seconds" -eq 0 ]; then
      # indefinite
      ( systemd-inhibit --what=sleep --why='Stay Alive' bash -c 'sleep infinity' ) &
      pid=$!
      expiry=0
    else
      ( systemd-inhibit --what=sleep --why='Stay Alive' bash -c "sleep $seconds" ) &
      pid=$!
      expiry=$(( $(date +%s) + seconds ))
    fi
    log "Started systemd-inhibit (pid=$pid) for ${seconds}s"
  else
    # Fallback: plain sleep (may not prevent system suspend under systemd)
    if [ "$seconds" -eq 0 ]; then
      ( sleep 2147483647 ) &
      pid=$!
      expiry=0
    else
      ( sleep "$seconds" ) &
      pid=$!
      expiry=$(( $(date +%s) + seconds ))
    fi
    log "Started fallback sleep (pid=$pid) for ${seconds}s (systemd-inhibit not available)"
  fi

  # Persist state
  echo "$pid" > "$PIDFILE"
  echo "$expiry" > "$EXPIREFILE"
  _notify "Stay Alive" "Enabled for $(format_seconds ${seconds})"
  log "Enabled stay-alive pid=$pid expiry=$expiry"
  return 0
}

stop_inhibitor() {
  if ! is_on; then
    _notify "Stay Alive" "Already off"
    log "stop_inhibitor(): nothing to stop"
    return 1
  fi
  pid=$(cat "$PIDFILE" 2>/dev/null || echo "")
  if [ -n "$pid" ]; then
    kill "$pid" >/dev/null 2>&1 || true
    # give it a brief moment to die
    sleep 0.1
    kill -0 "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$PIDFILE" "$EXPIREFILE" 2>/dev/null || true
  _notify "Stay Alive" "Disabled"
  log "Disabled stay-alive (killed pid=$pid)"
  return 0
}

status() {
  if is_on; then
    rem=$(remaining_seconds)
    if [ "$rem" = "forever" ]; then
      echo "on forever"
    else
      echo "on $(format_seconds $rem)"
    fi
  else
    echo "off"
  fi
}

# Allow toggle as shorthand
toggle() {
  if is_on; then
    stop_inhibitor
  else
    local duration="${1:-60m}"
    secs=$(parse_duration_to_seconds "$duration") || { echo "Invalid duration: $duration"; return 2; }
    start_inhibitor "$secs"
  fi
}

# Parse CLI
cmd="${1:-help}"
case "$cmd" in
  on)
    duration="${2:-60m}"
    force=0
    # allow optional --force flag as third parameter
    if [ "${3:-}" = "--force" ] || [ "${2:-}" = "--force" ]; then
      force=1
      # if duration was --force and no duration given, default to 60m
      if [ "${2:-}" = "--force" ]; then duration="60m"; fi
    fi
    secs=$(parse_duration_to_seconds "$duration") || { echo "Invalid duration: $duration"; exit 2; }
    if is_on && [ "$force" -eq 0 ]; then
      rem=$(remaining_seconds)
      if [ "$rem" = "forever" ]; then
        echo "Already on (forever)"
      else
        echo "Already on ($(format_seconds $rem))"
      fi
      exit 0
    fi
    if is_on && [ "$force" -eq 1 ]; then
      stop_inhibitor || true
    fi
    start_inhibitor "$secs"
    ;;
  off)
    stop_inhibitor
    ;;
  status|show)
    status
    ;;
  toggle)
    duration="${2:-60m}"
    toggle "$duration"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "Unknown command: $cmd"
    usage
    exit 2
    ;;
esac

exit 0
