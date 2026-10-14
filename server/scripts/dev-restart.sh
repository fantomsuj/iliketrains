#!/usr/bin/env bash
# Restart the local dev server (records live feeds into the demo folder). Dev helper only.
cd "$(dirname "$0")/.."
[ -f /var/tmp/trains-server.pid ] && kill "$(cat /var/tmp/trains-server.pid)" 2>/dev/null; sleep 1
TRAINS_RECORD_DIR="${TRAINS_RECORD_DIR-data/demo/2026-10-14-evening}" PORT="${PORT:-8787}" nohup node src/server.ts > /var/tmp/trains-server.log 2>&1 &
echo $! > /var/tmp/trains-server.pid
