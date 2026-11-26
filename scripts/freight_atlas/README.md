# Freight atlas pipeline

`build.py` turns public freight-rail data into `I Like Trains/Data/freight-atlas.json`, the file
behind the map's freight layers and the "Freight this week" sheet. Like the route atlas, it runs
offline and the app never downloads anything.

There is no public feed of where U.S. freight trains are right now. Everything here is real but
either a typical day (traffic, terminals) or last week (service, volume), and the app says so.

## Inputs

| Data | Publisher | How it gets here | Refresh |
| --- | --- | --- | --- |
| [Highway-Rail Crossing Inventory](https://data.transportation.gov/d/m2f8-22s6): train counts, timetable speed and main tracks at ~166k open crossings | FRA | `fetch.py` (Socrata API, no key) | Monthly |
| Class I main-line track | BTS North American Rail Network, via `route-atlas.json` | Already in the app | With the route atlas |
| [Intermodal Freight Facilities: Rail TOFC/COFC](https://geodata.bts.gov/datasets/usdot::intermodal-freight-facilities-rail-tofc-cofc), 241 ramps | BTS NTAD | `fetch.py` (ArcGIS REST); a copy is committed as `inputs/intermodal-ntad.json` | Yearly |
| [EP 724 rail service filings](https://www.stb.gov/reports-data/rail-service-data/): train speed, yard dwell, cars online, trains held | STB | Transcribed by hand into `inputs/stb-ep724.json` from each railroad's weekly spreadsheet | Weekly (Wednesdays) |
| [Weekly Rail Traffic](https://www.aar.org/data-center/rail-traffic-data/): U.S. carloads and intermodal units | AAR | Transcribed by hand into `inputs/aar-weekly.json` from the weekly PDF | Weekly (Wednesdays) |

The STB filings name each railroad's ten largest terminals but don't locate them, so the yard
coordinates in `stb-ep724.json` are approximate (city or yard level) and the app labels them that way.

## Traffic density method

1. **Freight trains per crossing.** Each crossing reports day and night *through* trains, and
   separately its passenger and transit trains. Freight = through − passenger − transit. Without
   this step, New York commuter lines show up as the busiest "freight" lines in the country.
   Counts above 150 a day are treated as data-entry errors and dropped.
2. **Chunk the track.** Every Class I main-line piece in the route atlas is cut into ~8 km chunks.
3. **Match crossings.** Each chunk takes the median freight count of crossings within 1 km that were
   reported by the same railroad family (BNSF, UP incl. SP/MP, CSX, NS, CN incl. IC/WC/GTW, CPKC
   incl. SOO/KCS). Crossings from other railroads count only within 350 m, so a parallel line in a
   city doesn't leak its traffic onto its neighbour.
4. **Fill short gaps.** A chunk with no crossings borrows from measured chunks up to three away
   (~24 km). Longer gaps stay unmeasured and draw as a thin dashed line.
5. **Merge.** Consecutive chunks in the same traffic band (0–5, 5–15, 15–30, 30–50, 50–80, 80+
   trains a day) become one corridor, labelled with its nearest atlas cities.

Spot checks against well-known lines: UP's Overland Route near North Platte, NE reads ~100 trains a
day, the BNSF Powder River coal lines ~58, the Chicago approaches 75–95. Crossing counts are
self-reported and updated irregularly, so expect them to run conservative on lines whose traffic
has grown.

## Regenerate

```sh
python3 scripts/freight_atlas/fetch.py /tmp/freight-raw            # ~10 requests, a few minutes
python3 scripts/freight_atlas/build.py \
  "I Like Trains/Data/route-atlas.json" /tmp/freight-raw scripts/freight_atlas/inputs \
  "I Like Trains/Data/freight-atlas.json"                         # a few seconds
python3 scripts/freight_atlas/test_build.py
python3 scripts/validate_project.py
```

Only the standard library is needed. Weekly refresh: update `stb-ep724.json` and `aar-weekly.json`
from that week's files, then rerun `build.py`.
