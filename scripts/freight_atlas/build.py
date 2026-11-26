#!/usr/bin/env python3
"""Build the bundled freight atlas from public rail data.

    python3 scripts/freight_atlas/build.py \
        "I Like Trains/Data/route-atlas.json" RAW_DIR scripts/freight_atlas/inputs \
        "I Like Trains/Data/freight-atlas.json"

RAW_DIR is the folder written by fetch.py (crossings/, optionally passenger/, and intermodal.json). The inputs folder holds
the hand-transcribed STB and AAR weekly figures; if RAW_DIR has no intermodal.json, the committed
inputs/intermodal-ntad.json is used.

Traffic density method
----------------------
Every public highway-rail crossing in the FRA inventory reports how many through trains cross it on
a typical day and night, and separately how many of those are passenger or transit trains; the
difference is the freight count used here. Those counts are the only nationwide, public, per-line measure of how busy
U.S. track is. The route atlas already holds every Class I railroad's main-line track as polylines.
This script cuts that track into ~8 km chunks, gives each chunk the median through-train count of
the crossings within ~1 km of it (preferring crossings reported by the same railroad family, so a
parallel line in a city doesn't leak its count), fills short gaps from neighbouring chunks, and
merges runs of chunks in the same traffic tier into corridors. Counts are self-reported by railroads
and states, updated irregularly, and describe a typical day, not today.
"""
from __future__ import annotations

import json
import math
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

CHUNK_KM = 8.0
MATCH_KM = 1.0            # crossing reported by the same railroad family
FOREIGN_MATCH_KM = 0.35   # crossing reported by another railroad (trackage rights, shared corridors)
FILL_CHUNKS = 3           # how far an unmeasured chunk may borrow a neighbour's count
MAX_PLAUSIBLE_TPD = 150   # the busiest U.S. freight main lines run ~100-120 trains a day
GRID_DEG = 0.05
SIMPLIFY_DEG = 0.0025

# Upper bounds (trains/day) of the tiers the map colours; runs in the same tier merge.
TIER_BOUNDS = (5, 15, 30, 50, 80)

# Crossing inventory reporting codes grouped by today's Class I parent, keyed like RailOperator.
FAMILIES = {
    "bnsf": {"BNSF", "BN", "ATSF", "SLSF", "BNSF-"},
    "unionPacific": {"UP", "SP", "MP", "CNW", "DRGW", "SSW", "MKT", "WP"},
    "csx": {"CSX", "CSXT", "SCL", "C&O", "B&O", "CO", "BO", "LN"},
    "norfolkSouthern": {"NS", "NW", "SOU", "CR", "CNJ", "NSR"},
    "canadianNational": {"CN", "IC", "WC", "GTW", "DWP", "DMIR", "EJE", "CCP", "BLE", "CNIC"},
    "canadianPacificKansasCity": {"CP", "SOO", "DME", "ICE", "KCS", "CPRS", "DMVW", "MILW", "TM", "CPKC"},
}
CODE_FAMILY = {code: family for family, codes in FAMILIES.items() for code in codes}

# Intermodal terminal RAIL_CO strings name Class I railroads by these tokens.
TERMINAL_RAILROADS = {
    "BNSF": "bnsf", "UP": "unionPacific", "CSX": "csx", "CSXT": "csx", "NS": "norfolkSouthern",
    "CN": "canadianNational", "CPKC": "canadianPacificKansasCity", "CP": "canadianPacificKansasCity",
    "KCS": "canadianPacificKansasCity",
}


# --- geometry -------------------------------------------------------------------------------

def decode_polyline(encoded: str) -> list[tuple[float, float]]:
    """Google encoded polyline -> [(lat, lon)]."""
    coords, index, lat, lon = [], 0, 0, 0
    while index < len(encoded):
        deltas = []
        for _ in range(2):
            result, shift = 0, 0
            while True:
                value = ord(encoded[index]) - 63
                index += 1
                result |= (value & 0x1F) << shift
                shift += 5
                if value < 0x20:
                    break
            deltas.append(~(result >> 1) if result & 1 else result >> 1)
        lat += deltas[0]
        lon += deltas[1]
        coords.append((lat / 1e5, lon / 1e5))
    return coords


def encode_polyline(coords: list[tuple[float, float]]) -> str:
    """[(lat, lon)] -> Google encoded polyline (precision 5)."""
    out, prev_lat, prev_lon = [], 0, 0
    for lat, lon in coords:
        ilat, ilon = round(lat * 1e5), round(lon * 1e5)
        for delta in (ilat - prev_lat, ilon - prev_lon):
            value = ~(delta << 1) if delta < 0 else delta << 1
            while value >= 0x20:
                out.append(chr((0x20 | (value & 0x1F)) + 63))
                value >>= 5
            out.append(chr(value + 63))
        prev_lat, prev_lon = ilat, ilon
    return "".join(out)


def km_between(a, b) -> float:
    kx = 111.32 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((b[1] - a[1]) * kx, (b[0] - a[0]) * 110.57)


def km_to_segment(p, a, b) -> float:
    """Distance from point p to segment ab in a local equirectangular projection (fine below ~50 km)."""
    kx = 111.32 * math.cos(math.radians(p[0]))
    ax, ay = (a[1] - p[1]) * kx, (a[0] - p[0]) * 110.57
    bx, by = (b[1] - p[1]) * kx, (b[0] - p[0]) * 110.57
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / length2))
    return math.hypot(ax + t * dx, ay + t * dy)


def km_to_path(p, path) -> float:
    return min(km_to_segment(p, a, b) for a, b in zip(path, path[1:]))


def chunk_path(path, chunk_km=CHUNK_KM):
    """Cuts a polyline into consecutive pieces of about chunk_km, sharing their end points."""
    chunks, current, run = [], [path[0]], 0.0
    for a, b in zip(path, path[1:]):
        step = km_between(a, b)
        start = a
        while step > 0 and run + step >= chunk_km:
            t = (chunk_km - run) / step
            cut = (start[0] + (b[0] - start[0]) * t, start[1] + (b[1] - start[1]) * t)
            current.append(cut)
            chunks.append(current)
            current, run = [cut], 0.0
            step -= km_between(start, cut)
            start = cut
        current.append(b)
        run += step
    if len(current) > 1 and (run > chunk_km * 0.25 or not chunks):
        chunks.append(current)
    elif len(current) > 1:
        chunks[-1].extend(current[1:])
    return chunks


def simplify(path, tolerance=SIMPLIFY_DEG):
    """Douglas-Peucker in degrees; keeps the end points."""
    if len(path) < 3:
        return path
    keep = [False] * len(path)
    keep[0] = keep[-1] = True
    stack = [(0, len(path) - 1)]
    while stack:
        first, last = stack.pop()
        a, b = path[first], path[last]
        best, index = 0.0, None
        for i in range(first + 1, last):
            p = path[i]
            dx, dy = b[1] - a[1], b[0] - a[0]
            if dx == 0 and dy == 0:
                distance = math.hypot(p[1] - a[1], p[0] - a[0])
            else:
                t = max(0.0, min(1.0, ((p[1] - a[1]) * dx + (p[0] - a[0]) * dy) / (dx * dx + dy * dy)))
                distance = math.hypot(p[1] - (a[1] + t * dx), p[0] - (a[0] + t * dy))
            if distance > best:
                best, index = distance, i
        if index is not None and best > tolerance:
            keep[index] = True
            stack.append((first, index))
            stack.append((index, last))
    return [p for p, k in zip(path, keep) if k]


# --- inputs ---------------------------------------------------------------------------------

def number(value, default=0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def load_passenger_counts(folder: Path) -> dict[str, float]:
    """Passenger plus transit trains per day by crossing ID, from an optional supplementary download."""
    counts = {}
    for page in sorted(folder.glob("p*.json")) if folder.exists() else []:
        for row in json.loads(page.read_text()):
            counts[row["crossingid"]] = number(row.get("numberpassengertrainperday")) + number(row.get("totaltransittrains"))
    return counts


def load_crossings(folder: Path, passenger_counts: dict[str, float] | None = None) -> list[dict]:
    """Crossings with a plausible count of *freight* trains: through trains minus passenger and transit trains."""
    passenger_counts = passenger_counts or {}
    seen, crossings = set(), []
    for page in sorted(folder.glob("p*.json")):
        for row in json.loads(page.read_text()):
            crossing_id = row.get("crossingid")
            if not crossing_id or crossing_id in seen:
                continue
            seen.add(crossing_id)
            lat, lon = number(row.get("latitude"), None), number(row.get("longitude"), None)
            if lat is None or lon is None or not (17 < lat < 72) or not (-170 < lon < -60):
                continue
            through = number(row.get("totaldaylightthrutrains")) + number(row.get("totalnighttimethrutrains"))
            if through <= 0 or through > MAX_PLAUSIBLE_TPD:
                continue
            if "numberpassengertrainperday" in row or "totaltransittrains" in row:
                passenger = number(row.get("numberpassengertrainperday")) + number(row.get("totaltransittrains"))
            else:
                passenger = passenger_counts.get(crossing_id, 0.0)
            freight = max(0.0, through - passenger)
            crossings.append({
                "lat": lat, "lon": lon, "tpd": freight,
                "mph": number(row.get("maximumtimetablespeed")),
                "tracks": int(number(row.get("numberofmaintracks"))),
                "family": CODE_FAMILY.get((row.get("railroadcode") or "").strip().upper()),
            })
    return crossings


class CrossingIndex:
    def __init__(self, crossings):
        self.cells = defaultdict(list)
        for crossing in crossings:
            self.cells[self.cell(crossing["lat"], crossing["lon"])].append(crossing)

    @staticmethod
    def cell(lat, lon):
        return int(math.floor(lat / GRID_DEG)), int(math.floor(lon / GRID_DEG))

    def near(self, path, km):
        pad = km / 100 + GRID_DEG
        lats, lons = [p[0] for p in path], [p[1] for p in path]
        (r0, c0), (r1, c1) = self.cell(min(lats) - pad, min(lons) - pad), self.cell(max(lats) + pad, max(lons) + pad)
        for row in range(r0, r1 + 1):
            for column in range(c0, c1 + 1):
                for crossing in self.cells.get((row, column), ()):
                    distance = km_to_path((crossing["lat"], crossing["lon"]), path)
                    if distance <= km:
                        yield crossing, distance


# --- traffic density ------------------------------------------------------------------------

def tier(tpd):
    if tpd is None:
        return -1
    return sum(tpd >= bound for bound in TIER_BOUNDS)


def measure_chunk(chunk, railroad, index):
    own, foreign = [], []
    for crossing, distance in index.near(chunk, MATCH_KM):
        if crossing["family"] == railroad:
            own.append(crossing)
        elif distance <= FOREIGN_MATCH_KM:
            foreign.append(crossing)
    sample = own or foreign
    if not sample:
        return None
    speeds = [c["mph"] for c in sample if c["mph"] > 0]
    tracks = [c["tracks"] for c in sample if c["tracks"] > 0]
    return {
        "tpd": statistics.median(c["tpd"] for c in sample),
        "mph": statistics.median(speeds) if speeds else None,
        "tracks": Counter(tracks).most_common(1)[0][0] if tracks else None,
        "n": len(sample),
    }


def fill_gaps(measures):
    """Unmeasured chunks borrow from the nearest measured neighbours within FILL_CHUNKS."""
    filled = list(measures)
    for i, measure in enumerate(measures):
        if measure is not None:
            continue
        left = next((measures[j] for j in range(i - 1, max(-1, i - FILL_CHUNKS - 1), -1) if measures[j]), None)
        right = next((measures[j] for j in range(i + 1, min(len(measures), i + FILL_CHUNKS + 1)) if measures[j]), None)
        neighbours = [m for m in (left, right) if m]
        if neighbours:
            filled[i] = {
                "tpd": sum(m["tpd"] for m in neighbours) / len(neighbours),
                "mph": next((m["mph"] for m in neighbours if m["mph"]), None),
                "tracks": next((m["tracks"] for m in neighbours if m["tracks"]), None),
                "n": 0,
            }
    return filled


def corridors_for_piece(path, railroad, index):
    chunks = chunk_path(path)
    measures = fill_gaps([measure_chunk(chunk, railroad, index) for chunk in chunks])
    runs, current = [], None
    for chunk, measure in zip(chunks, measures):
        level = tier(measure["tpd"] if measure else None)
        if current and current["tier"] == level:
            current["path"].extend(chunk[1:])
            current["measures"].append(measure)
        else:
            current = {"tier": level, "path": list(chunk), "measures": [measure]}
            runs.append(current)
    corridors = []
    for run in runs:
        measured = [m for m in run["measures"] if m]
        speeds = [m["mph"] for m in measured if m["mph"]]
        tracks = [m["tracks"] for m in measured if m["tracks"]]
        corridors.append({
            "rr": railroad,
            "tpd": round(statistics.median(m["tpd"] for m in measured), 1) if measured else None,
            "mph": round(statistics.median(speeds)) if speeds else None,
            "tracks": Counter(tracks).most_common(1)[0][0] if tracks else None,
            "n": sum(m["n"] for m in measured),
            "path": encode_polyline(simplify(run["path"])),
        })
    return corridors


def bearing_word(a, b):
    dx = (b[1] - a[1]) * math.cos(math.radians((a[0] + b[0]) / 2))
    dy = b[0] - a[0]
    angle = (math.degrees(math.atan2(dx, dy)) + 360) % 360
    return ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][int((angle + 22.5) // 45) % 8]


def describe_place(path, cities):
    """'Chicago, IL – Galesburg, IL' when both ends sit near atlas cities, else '40 mi west of Denver, CO'."""
    def nearest(point):
        return min(((km_between(point, (c["lat"], c["lon"])), c) for c in cities), key=lambda item: item[0])

    (start_km, start), (end_km, end) = nearest(path[0]), nearest(path[-1])
    if start["id"] != end["id"] and start_km <= 40 and end_km <= 40:
        return f"{start['name']}, {start['region']} – {end['name']}, {end['region']}"
    middle = path[len(path) // 2]
    km, city = nearest(middle)
    label = f"{city['name']}, {city['region']}"
    if km < 15:
        return f"Near {label}"
    return f"{round(km / 1.609):,} mi {bearing_word((city['lat'], city['lon']), middle)} of {label}"


def build_corridors(atlas, crossings):
    index = CrossingIndex(crossings)
    corridors = []
    for track in atlas["freightTrack"]:
        for piece in track["pieces"]:
            path = decode_polyline(piece)
            if len(path) >= 2:
                corridors.extend(corridors_for_piece(path, track["railroad"], index))
    for corridor in corridors:
        corridor["place"] = describe_place(decode_polyline(corridor["path"]), atlas["cities"])
    return corridors


# --- terminals, service, volume ------------------------------------------------------------

def slug(text: str) -> str:
    return "-".join("".join(ch.lower() if ch.isalnum() else " " for ch in text).split())


def build_terminals(rows):
    terminals, seen = [], set()
    for row in rows:
        lat, lon = number(row.get("LAT"), None), number(row.get("LON"), None)
        if lat is None or lon is None:
            continue
        name = (row.get("TERMINAL") or "").strip() or "Intermodal terminal"
        city, state = (row.get("CITY") or "").strip(), (row.get("STATE") or "").strip()
        terminal_id = slug(f"{state} {city} {name}")
        if terminal_id in seen:
            terminal_id = f"{terminal_id}-{len(seen)}"
        seen.add(terminal_id)
        operators_text = (row.get("RAIL_CO") or "").strip()
        tokens = operators_text.replace("/", " ").replace(",", " ").replace(";", " ").split()
        railroads = sorted({TERMINAL_RAILROADS[t] for t in tokens if t in TERMINAL_RAILROADS})
        port = (row.get("PORT") or "").strip()
        equipment = (row.get("EQUIPMENT") or "").strip().upper()
        terminals.append({
            "id": terminal_id, "name": name, "city": city, "state": state,
            "port": port or None, "operators": operators_text, "railroads": railroads,
            "trailers": "TOFC" in equipment, "containers": "COFC" in equipment,
            "lat": round(lat, 5), "lon": round(lon, 5),
        })
    return terminals


def main() -> None:
    if len(sys.argv) != 5:
        raise SystemExit(__doc__)
    atlas_path, raw_dir, inputs_dir, out_path = map(Path, sys.argv[1:])
    atlas = json.loads(atlas_path.read_text())
    passenger_counts = load_passenger_counts(raw_dir / "passenger")
    crossings = load_crossings(raw_dir / "crossings", passenger_counts)
    print(len(crossings), "crossings with plausible train counts;", len(passenger_counts), "with passenger trains", file=sys.stderr)

    intermodal_path = raw_dir / "intermodal.json"
    if not intermodal_path.exists():
        intermodal_path = inputs_dir / "intermodal-ntad.json"
    stb = json.loads((inputs_dir / "stb-ep724.json").read_text())
    aar = json.loads((inputs_dir / "aar-weekly.json").read_text())

    corridors = build_corridors(atlas, crossings)
    measured = [c for c in corridors if c["tpd"] is not None]
    print(f"{len(corridors)} corridors, {len(measured)} with counts", file=sys.stderr)

    result = {
        "version": 1,
        "sources": [
            {
                "id": "crossings", "name": "Highway-Rail Crossing Inventory",
                "publisher": "Federal Railroad Administration",
                "url": "https://data.transportation.gov/d/m2f8-22s6",
                "asOf": "2026-11", "detail": f"{len(crossings):,} open crossings with through-train counts",
            },
            {
                "id": "track", "name": "North American Rail Network Lines",
                "publisher": "Bureau of Transportation Statistics",
                "url": "https://geodata.bts.gov/datasets/usdot::north-american-rail-network-lines",
                "asOf": "2025", "detail": "Class I main-line track, via the route atlas",
            },
            {
                "id": "intermodal", "name": "Intermodal Freight Facilities: Rail TOFC/COFC",
                "publisher": "Bureau of Transportation Statistics",
                "url": "https://geodata.bts.gov/datasets/usdot::intermodal-freight-facilities-rail-tofc-cofc",
                "asOf": "2025-02", "detail": "Container and trailer ramps",
            },
            {
                "id": "service", "name": "Rail Service Data (EP 724)",
                "publisher": "Surface Transportation Board",
                "url": stb["url"], "asOf": stb["weekEnded"], "detail": "Weekly filings by each Class I railroad",
            },
            {
                "id": "volume", "name": "Weekly Rail Traffic",
                "publisher": "Association of American Railroads",
                "url": aar["url"], "asOf": aar["weekEnded"], "detail": "U.S. carloads and intermodal units",
            },
        ],
        "tierBounds": list(TIER_BOUNDS),
        "corridors": corridors,
        "terminals": build_terminals(json.loads(intermodal_path.read_text())),
        "service": {
            "weekBegan": stb["weekBegan"], "weekEnded": stb["weekEnded"],
            "railroads": stb["railroads"],
        },
        "volume": {k: aar[k] for k in ("week", "weekEnded", "totalCarloads", "intermodalUnits", "totalTraffic", "commodities")},
    }
    Path(out_path).write_text(json.dumps(result, separators=(",", ":")))
    print(f"wrote {out_path} ({Path(out_path).stat().st_size / 1e6:.2f} MB)", file=sys.stderr)


if __name__ == "__main__":
    main()
