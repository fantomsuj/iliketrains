# Route atlas pipeline

`build.py` turns two public datasets into `I Like Trains/Data/route-atlas.json`, the file behind the
Routes screen. It runs offline; the app never downloads anything.

## Inputs

| Dataset | Publisher | Used for |
| --- | --- | --- |
| [North American Rail Network Lines](https://geodata.bts.gov/datasets/usdot::north-american-rail-network-lines) (GeoJSON, ~400 MB, ~300k segments) | BTS National Transportation Atlas Database, from FRA data | The track graph: owning railroad, trackage rights, passenger flag, subdivision, mileage |
| [Amtrak Routes](https://geodata.bts.gov/datasets/usdot::amtrak-routes) (shapefile) | BTS NTAD | Guide lines only, so each service follows the right track between its cities |

## What it builds

**Passenger services.** `routes.py` lists every Amtrak service (plus Brightline) as an ordered list of
cities, matching the 2025 network. For each pair of consecutive cities the pipeline finds the
cheapest path on the rail network, where track flagged for passenger use, and track near the
service's BTS guide line, is cheap. Output: the traced line, its mileage (summed from the NARN
segment mileage) and the mile marker of every atlas city it passes within 9 km of. City-to-city
mileage is the difference of two mile markers.

**Freight railroads.** For each Class I railroad (BNSF, UP, CSX, NS, CN, CPKC) the pipeline keeps
only the segments it owns or holds trackage rights on, snaps each freight hub in `cities.py` to that
network, and runs Dijkstra from every hub (yards and industry track cost more than main line). The
union of shortest paths from a hub is a tree; each branch records how many destination hubs it
carries, which the app uses for line width. Track is stored once per railroad as pieces between
junctions, and trees reference pieces, which keeps the file around 1 MB instead of 3+.

## Regenerate

```sh
pip install networkx numpy shapely pyshp
python3 scripts/route_atlas/build.py \
  NTAD_North_American_Rail_Network_Lines.geojson \
  amtrak_routes.shp \
  "I Like Trains/Data/route-atlas.json"
```

A full run takes about 15 minutes; the parsed network is cached next to the GeoJSON.

## Caveats

- These are the shortest single-railroad routes, not the routes trains are actually dispatched on,
  and they ignore interchange between railroads.
- Mile markers come from track geometry, so they can differ from Amtrak timetable mileage by a few
  percent.
- Passenger city lists are hand-maintained in `routes.py`; update them when Amtrak changes service.
