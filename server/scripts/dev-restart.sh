#!/usr/bin/env bash
# Restart the local dev server (set TRAINS_RECORD_DIR to capture feeds). Dev helper only.
cd "$(dirname "$0")/.."
[ -f /var/tmp/trains-server.pid ] && kill "$(cat /var/tmp/trains-server.pid)" 2>/dev/null; sleep 1
TRAINS_RECORD_DIR="${TRAINS_RECORD_DIR:-}" PORT="${PORT:-8787}" nohup node src/server.ts > /var/tmp/trains-server.log 2>&1 &
echo $! > /var/tmp/trains-server.pid
