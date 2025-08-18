#!/usr/bin/env bash
set -Eeuo pipefail

# Detach from Coder pipes
exec </dev/null >/dev/null 2>&1

mkdir -p /home/coder/data/logs

if ! pgrep -f "/home/coder/srv/scripts/process-manager.sh monitor" >/dev/null 2>&1; then
  setsid sh -c 'exec /home/coder/srv/scripts/process-manager.sh monitor >> /home/coder/data/logs/process-monitor.log 2>&1' </dev/null >/dev/null 2>&1 &
fi

exit 0
