#!/usr/bin/env bash
# Build the Trains basemap: Geofabrik extracts -> railway-only OSM -> planetiler -> PMTiles.
#
# Usage: tiles/build.sh            (work dir defaults to $TRAINS_TILES_WORK or /var/tmp/trains-osm)
# Output: tiles/dist/trains.pmtiles and tiles/dist/rail.osm.pbf (the latter feeds the
#         server's offline route matcher, see server/src/build/build-routes.ts).
#
# Needs: curl, osmium-tool, node >= 22, java >= 21. Peak memory stays under ~1.2 GB.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${TRAINS_TILES_WORK:-/var/tmp/trains-osm}"
SOURCES="$WORK/sources"
DIST="$HERE/dist"
# Region = Geofabrik US Northeast + the rest of the Northeast Corridor down to Washington.
EXTRACTS=(
  "north-america/us-northeast"
  "north-america/us/delaware"
  "north-america/us/maryland"
  "north-america/us/district-of-columbia"
)
BOUNDS="-80.6,38.6,-66.8,47.6"
PLANETILER_URL="https://github.com/onthegomap/planetiler/releases/latest/download/planetiler.jar"
export OSMIUM_POOL_THREADS=1
mkdir -p "$WORK" "$SOURCES" "$DIST"

fetch() { # fetch <url> <dest> -- skip if present
  [ -s "$2" ] || { echo "downloading $1"; curl -fsSL -A "TrainsMVP-tiles/0.1" -o "$2.part" "$1" && mv "$2.part" "$2"; }
}

fetch "$PLANETILER_URL" "$SOURCES/planetiler.jar"
fetch "https://osmdata.openstreetmap.de/download/water-polygons-split-4326.zip" "$SOURCES/water-polygons-split-4326.zip"
fetch "https://naciscdn.org/naturalearth/10m/physical/ne_10m_lakes.zip" "$SOURCES/ne_10m_lakes.zip"

parts=()
for ex in "${EXTRACTS[@]}"; do
  name="$(basename "$ex")"
  full="$WORK/$name-latest.osm.pbf"
  fetch "https://download.geofabrik.de/$ex-latest.osm.pbf" "$full"
  out="$WORK/$name.rail.osm.pbf"
  if [ ! -s "$out" ] || [ "$full" -nt "$out" ]; then
    echo "filtering $name"
    # 1. railway objects + stations + place labels, WITHOUT referenced nodes (-R).
    #    Plain tags-filter / getid allocate ~2 GB id bitmaps and get OOM-killed on small boxes.
    osmium tags-filter -R "$full" \
      w/railway n/railway n/public_transport=station r/public_transport=stop_area \
      n/place=city,town -o "$WORK/$name.noref.osm.pbf" --overwrite
    # 2. node ids the ways reference
    osmium cat "$WORK/$name.noref.osm.pbf" -t way -f opl | grep -oE " N[^ ]*" | tr ',' '\n' \
      | sed -E 's/^ ?N//' | grep -E '^n[0-9]+' | sort -u > "$WORK/$name.ids.txt"
    # 3. stream the full extract once and keep just those nodes (low memory)
    node "$HERE/scripts/extract-way-nodes.mjs" "$full" "$WORK/$name.ids.txt" "$WORK/$name.waynodes.osm"
    # 4. drop nodes already present (tagged) in the noref file, then merge
    osmium cat "$WORK/$name.noref.osm.pbf" -t node -f opl | awk '{print "<node id=\"" substr($1,2) "\" "}' > "$WORK/$name.tagged.txt"
    grep -vF -f "$WORK/$name.tagged.txt" "$WORK/$name.waynodes.osm" > "$WORK/$name.waynodes.untagged.osm" || true
    osmium cat "$WORK/$name.waynodes.untagged.osm" -o "$WORK/$name.waynodes.osm.pbf" --overwrite
    osmium merge "$WORK/$name.noref.osm.pbf" "$WORK/$name.waynodes.osm.pbf" -o "$out" --overwrite
    rm -f "$WORK/$name.waynodes.osm" "$WORK/$name.waynodes.untagged.osm"
  fi
  parts+=("$out")
done

echo "merging regions"
osmium merge "${parts[@]}" -o "$DIST/rail.osm.pbf" --overwrite
osmium check-refs "$DIST/rail.osm.pbf"

echo "running planetiler"
java -Xmx1g -jar "$SOURCES/planetiler.jar" generate-custom \
  --schema="$HERE/trains.yml" \
  --rail_path="$DIST/rail.osm.pbf" \
  --water_path="$SOURCES/water-polygons-split-4326.zip" \
  --lakes_path="$SOURCES/ne_10m_lakes.zip" \
  --bounds="$BOUNDS" --maxzoom=14 --nodemap-type=sparsearray --storage=mmap \
  --output="$DIST/trains.pmtiles" --force
ls -la "$DIST"
