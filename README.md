# Trains

Flighty for trains: a live map of every passenger train in the US Northeast (Amtrak, LIRR, Metro-North,
NJ Transit), moving smoothly along the actual track. Tap a train for its route, next stops and delay;
tap a station for every train at it.

Browser preview of the same data (the iPhone screens follow the same layout):
`docs/screenshots/network-map.png`, `train-card.png`, `station-board.png`.

```
ios/      SwiftUI + MapLibre Native app, plus TrainsCore (models, motion, geometry; tested on Linux too)
server/   Node/TypeScript service: polls feeds, positions trains on track, pushes over WebSocket/SSE
tiles/    OpenStreetMap -> railway-only extract -> planetiler -> PMTiles, and the dark map style
```

## Quick start (demo mode, no network feeds needed)

```sh
# 1. map tiles (one-off; downloads ~2 GB of OSM extracts, peak memory ~1.2 GB)
tiles/build.sh                      # needs osmium-tool, node >= 22, java >= 21

# 2. server
cd server
npm install
npm run fetch:gtfs                  # static timetables for all four railroads (~100 MB unpacked)
npm run build:routes                # snap every timetable route onto OSM track (~2 min)
npm run demo                        # replays the recorded evening in server/data/demo/
open http://localhost:8787          # browser preview of the network map (development aid)

# 3. iOS app
cd ../ios
brew install xcodegen && xcodegen   # generates Trains.xcodeproj from project.yml
open Trains.xcodeproj               # run on an iOS 17+ simulator
```

Live mode is `npm start` instead of `npm run demo`. Node 22 runs the TypeScript sources directly (type stripping), so there is no build step.

On a device, set `TRAINS_SERVER_URL` in `ios/project.yml` (or the `serverURL` user default) to your Mac's LAN address.

## Environment

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `8787` | HTTP + WebSocket port |
| `TRAINS_DEMO` | unset | `1` replays `TRAINS_DEMO_DIR` instead of polling feeds |
| `TRAINS_DEMO_DIR` | `server/data/demo/2026-10-14-evening` | recording to replay |
| `TRAINS_RECORD_DIR` | unset | while live, save every raw feed response here (`<feed>/<epochMs>.bin.gz`); cut a demo with `node scripts/make-demo.ts` |
| `POLL_SECONDS` | `20` | poll interval for MTA/NJT (Amtraker is never polled faster than 30 s) |
| `TRAINS_USER_AGENT` | `TrainsMVP/0.1 ...` | sent to every feed; put a contact address here before running publicly |
| `AMTRAKER_URL` | `https://api-v3.amtraker.com/v3/trains` | point at a self-hosted [amtraker-v3](https://github.com/piemadd/amtraker-v3) later |
| `MTA_LIRR_URL`, `MTA_MNR_URL` | MTA public endpoints | no key needed |
| `NJT_API_TOKEN` or `NJT_USERNAME` + `NJT_PASSWORD` | unset | NJ Transit GTFS-RT. Without them NJ Transit trains are shown from the timetable, labelled "Scheduled" |
| `NJT_BASE_URL` | `https://raildata.njtransit.com/api/GTFSRT` | NJ Transit developer API |
| `TILES_URL` | this server | public URL of `trains.pmtiles` on the CDN |
| `GLYPHS_URL` | Protomaps font CDN | label fonts for the map style |
| `ROUTES_FILE`, `TILES_FILE` | `server/data/derived/routes.json`, `tiles/dist/trains.pmtiles` | build outputs |

## API

- `GET /api/snapshot` - all trains (summary form) + recent events
- `WS /live` (or `GET /live/sse`) - `snapshot`, then `trains` (per feed poll: changed + removed) and `event` messages
- `GET /api/trains/:id` - one train with every stop
- `GET /api/stations`, `GET /api/stations/:hubId/board` - station hubs and their boards
- `GET /api/search?q=` - trains by number/route, stations by name or Amtrak code
- `GET /api/routes`, `GET /api/shapes/:key` - route geometry (encoded polylines)
- `GET /style.json[?tiles=xyz]`, `GET /tiles/trains.pmtiles`, `GET /tiles/{z}/{x}/{y}.mvt` - map
- `GET /health` - per-feed status, last success, errors, train counts

## Map data and the tile pipeline

`tiles/build.sh` downloads Geofabrik's US Northeast extract plus Delaware, Maryland and DC (the
Northeast Corridor runs to Washington, which the "US Northeast" extract stops short of), keeps only
railway objects, stations and city/town labels, and runs planetiler with `tiles/trains.yml`. Output:
`tiles/dist/trains.pmtiles` (~23 MB) and `tiles/dist/rail.osm.pbf`, which feeds the route matcher.

The usual `osmium tags-filter` pass that adds referenced nodes allocates ~2 GB of id bitmaps regardless of
output size and gets killed on small machines, so the script filters ways without their nodes and
pulls the needed nodes with a streaming extractor (`tiles/scripts/extract-way-nodes.mjs`, ~100 MB).

No hosted OSM tile servers are used. To publish, upload `trains.pmtiles` to any CDN that supports HTTP
range requests and CORS (Cloudflare R2, S3 + CloudFront) and set `TILES_URL`. The iOS app defaults to
the server's z/x/y endpoint (`useXYZTiles`), which needs no PMTiles support in the client; switch it
off to read the CDN file directly.

**Licensing.** The tiles and `server/data/derived/routes.json` are derived from OpenStreetMap and are
under the ODbL; they are kept apart from everything else (see `server/data/derived/README.md`). Every
map shows "© OpenStreetMap contributors". Water polygons come from osmdata.openstreetmap.de (also OSM);
lakes at low zoom from Natural Earth (public domain). Timetables are the railroads' published GTFS.
Amtraker is unofficial and volunteer-run: we send an identifying User-Agent, poll it at most every 30 s,
and cache responses.

## How trains are positioned

1. **Offline: snap routes onto track** (`server/src/build/`). A rail graph is built from the OSM
   ways (`railway=rail`, yards and sidings made expensive). Each timetable shape is resampled every
   80 m and matched with a hidden Markov model (Newson & Krumm): candidates on nearby track,
   Viterbi over emission (distance to track) and transition (track distance vs. straight-line
   distance). Track paths between chosen candidates are stitched into the route line; gaps in OSM
   fall back to the raw shape and are counted as breaks. Trips with no shape (some Amtrak) are routed
   station-to-station over the graph. Each stop pattern stores its stops' distance along the line.
   Result: LIRR, NJ Transit and Metro-North rail routes 100% on track; Amtrak 100% within the mapped
   states.
2. **Runtime: distance along the route** (`server/src/live/positioner.ts`). A GPS report is
   projected onto the route within a window around the current stops; a fix that implies an
   impossible move is held until a second report confirms it; when GPS drops out the train keeps
   dead-reckoning on its last fix. Without GPS, position comes from live stop predictions, or from the
   timetable (then labelled "Scheduled"). The server sends a **motion plan**: an anchor (distance, time),
   upcoming stops with predicted arrival/departure, a fallback speed and a speed cap.
3. **Client: animate** (`ios/TrainsCore/.../Motion.swift`, same rules as `server/src/motion.ts`).
   Each frame the plan gives a target distance: constant speed to the next predicted arrival (never
   above the cap, so an optimistic prediction makes the train late rather than fast), dwell until
   departure. The drawn position eases toward the target, never moves backward (it pauses), and a
   large correction fades the marker out and back in rather than sliding it in reverse.

Measured on the live feed (Oct 14, 2026, evening): GPS-fixed Amtrak trains sit a median 3 m (max 38 m)
from the reported point. Between consecutive updates, 0.6% of trains needed a correction over 2 km,
typically a train dwelling longer than predicted.

## Screens and where their design comes from

**Network map** - borrows Flighty's calm dark map with glowing route lines and LiveATC's sense of
watching a whole system at once. Adapted for rail: the lines are the actual tracks each route uses
(not great-circle arcs); a train's dot is its line's colour so you can tell a Harlem Line train from a
Hudson Line one at a glance, and only lateness adds a ring (amber 5+ min, red 15+ min or cancelled),
because a red New Haven Line dot must not read as "late". Hollow dots are timetable-only.
The bottom strip is the ATC "listening in" feed: departures, arrivals, delay jumps and
cancellations as they happen ("Acela 2153 departed NYP, 4 min late"), monospaced like a radio log.

**Train card** - Flighty's live-tracking card: operator and line, the big number, then one big
colour-coded status ("12 min late" in amber) with a small badge for how we know (Live GPS / Live
times / Scheduled). Origin and destination codes sit either side of a live countdown to the next stop,
over a progress rail whose marker is the same position drawn on the map, frame by frame. Below, every
stop with the scheduled time struck through when it differs. Trains differ from flights in having many
intermediate stops, so the stop list is the card's spine rather than a detail. Medium haptic when the
train departs or arrives somewhere while the card is open; the map camera rides along with the train.

**Station board** - Flighty's "all planes at this airport", for a station: departures and arrivals
for the next three hours across every railroad that serves it (New York Penn = Amtrak + NJ Transit +
LIRR in one board). Time in big tabular digits coloured by punctuality, track when the feed gives one,
live trains tappable into their card, timetable-only trains shown dimmer as "Scheduled".

**Search** - Flighty's flight-number search: type a train number ("2153") or a station ("Penn",
"NYP"); exact train-number matches first.

**Personality** - Carrot/Not Boring touches kept small: playful copy on the card ("Arrived. That's a
wrap.", "Quiet right now"), numeric text transitions on counts and countdowns, selection haptics,
pulsing live dot.

## Tests

```sh
cd server && npm test          # map matching, motion vectors, positioning, stations, demo replay end-to-end
cd ios/TrainsCore && swift test   # same motion vectors in Swift, geometry, animator, decoding real server output
```

`server/test/fixtures/motion-vectors.json` holds hand-worked expectations both implementations must meet.

Dev checks against the live feeds: `node scripts/check-positions.ts` (our position vs each feed's raw
GPS) and `node scripts/watch-jumps.ts 180` (corrections over 2 km between updates).

## Status

Works: tile pipeline and dark map; Amtrak, LIRR and Metro-North live positions on track; NJ Transit
from the timetable; smooth motion; station boards, train detail, search, live event ticker; WebSocket
and SSE push; demo replay; browser preview.

Not verified: the SwiftUI/MapLibre app target has not been compiled. It was written on Linux
without Xcode; the shared TrainsCore package and the app's networking layer were compiled and tested, the
screens were only syntax-checked. Expect a short round of compile fixes on first build.

### Data gaps

- **NJ Transit realtime** needs a developer account; until `NJT_*` is set NJ Transit is timetable-only, and the token flow is written to NJT's published API but untested.
- **Track numbers**: MTA publishes them in a GTFS-RT extension the standard bindings don't decode; Amtraker's platform field is mostly empty. Boards show tracks only when present.
- **Amtrak GPS lag**: Amtraker positions are often 2-10 minutes old and sometimes contradict the stop statuses; those trains are dead-reckoned from the last fix.
- **Amtrak timetable** published on Oct 14 starts on Oct 15, so today's Amtrak trains that Amtraker doesn't list yet are missing from station boards.
- **Long Island positions**: about 10% of vehicle reports are over 30 minutes old and are ignored (the train is placed from stop predictions).
- **Metro-North** sometimes alternates between two GPS reports for the same train; filtered as above.
- **Outside the map region** (Virginia, Ontario, Quebec) long-distance Amtrak trains follow the raw timetable shape, not snapped track.
- **Bus substitutions** listed in the Metro-North timetable (e.g. "Bridgeport (Bus)") are shown as trains on road geometry.
- **Demo mode** replays recorded feeds but needs the current static timetables; a recording from a date the timetable no longer covers loses timetable-only trains.

### Open questions

1. Hosting: which CDN for the PMTiles file, and is a server near the feeds (us-east) fine?
2. Should Amtrak long-distance trains be shown once they leave the Northeast, or hidden at the region edge?
3. Amtraker: ask its maintainer before relying on it, or self-host amtraker-v3 from the start?
4. Map rendering on device: trains are redrawn as one GeoJSON source each frame (30-60 fps). Fine for ~450 trains in theory; needs a check on an older iPhone, with a custom Metal layer as the fallback.
5. Should bus substitutions appear on a trains map at all?
