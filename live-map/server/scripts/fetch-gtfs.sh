#!/usr/bin/env bash
# Download and unpack static GTFS for every feed into server/data/gtfs/<feed>/.
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
UA="TrainsMVP/0.1 (+https://github.com/trains-app)"
declare -A FEEDS=(
  [amtrak]="https://content.amtrak.com/content/gtfs/GTFS.zip"
  [lirr]="https://rrgtfsfeeds.s3.amazonaws.com/gtfslirr.zip"
  [mnr]="https://rrgtfsfeeds.s3.amazonaws.com/gtfsmnr.zip"
  [njt]="https://www.njtransit.com/rail_data.zip"
)
for feed in "${!FEEDS[@]}"; do
  dir="$HERE/data/gtfs/$feed"; mkdir -p "$dir"
  echo "fetching $feed"
  curl -fsSL -A "$UA" -o "$dir.zip" "${FEEDS[$feed]}"
  unzip -o -q "$dir.zip" -d "$dir" && rm "$dir.zip"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$dir/.fetched_at"
done
