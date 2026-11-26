#!/usr/bin/env python3
"""Download the public datasets behind the freight atlas.

    python3 scripts/freight_atlas/fetch.py OUT_DIR

Writes:
  OUT_DIR/crossings/pNNN.json   FRA Highway-Rail Crossing Inventory rows (open crossings with through trains)
  OUT_DIR/intermodal.json       BTS NTAD rail intermodal (TOFC/COFC) terminals

Both are U.S. government works with no API key required. The STB and AAR weekly figures are small
and published as spreadsheets and PDFs, so they are transcribed into inputs/*.json by hand each week
(see README.md in this folder).
"""
from __future__ import annotations

import json
import sys
import urllib.parse
import urllib.request
from pathlib import Path

CROSSINGS = "https://data.transportation.gov/resource/m2f8-22s6.json"
CROSSING_FIELDS = [
    "crossingid", "railroadcode", "latitude", "longitude",
    "totaldaylightthrutrains", "totalnighttimethrutrains", "totalswitchingtrains",
    "maximumtimetablespeed", "numberofmaintracks",
    "numberpassengertrainperday", "totaltransittrains",
]
CROSSING_FILTER = (
    "crossingclosed='No' AND (totaldaylightthrutrains>0 OR totalnighttimethrutrains>0) "
    "AND latitude IS NOT NULL"
)
INTERMODAL = (
    "https://services.arcgis.com/xOi1kZaI0eWDREZv/ArcGIS/rest/services/"
    "NTAD_Intermodal_Freight_Facilities_Rail_TOFC_COFC/FeatureServer/0/query"
)
PAGE = 20_000


def get_json(url: str, params: dict[str, str]):
    request = urllib.request.Request(
        f"{url}?{urllib.parse.urlencode(params)}",
        headers={"User-Agent": "iliketrains-freight-atlas/1.0"},
    )
    with urllib.request.urlopen(request, timeout=300) as response:
        return json.load(response)


def fetch_crossings(out: Path) -> int:
    """Keyset-paginates on crossing ID, which is stable while the dataset refreshes monthly."""
    out.mkdir(parents=True, exist_ok=True)
    last, page, total = "", 0, 0
    while True:
        where = CROSSING_FILTER + (f" AND crossingid>'{last}'" if last else "")
        rows = get_json(CROSSINGS, {
            "$select": ",".join(CROSSING_FIELDS),
            "$where": where,
            "$order": "crossingid",
            "$limit": str(PAGE),
        })
        if not rows:
            break
        (out / f"p{page:03d}.json").write_text(json.dumps(rows))
        total += len(rows)
        print(f"crossings page {page}: {len(rows)} rows (through {rows[-1]['crossingid']})", file=sys.stderr)
        last, page = rows[-1]["crossingid"], page + 1
        if len(rows) < PAGE:
            break
    return total


def fetch_intermodal(out: Path) -> int:
    data = get_json(INTERMODAL, {
        "where": "1=1",
        "outFields": "TERMINAL,CITY,STATE,PORT,RAIL_CO,EQUIPMENT,LAT,LON",
        "returnGeometry": "false",
        "orderByFields": "STATE,CITY",
        "resultRecordCount": "2000",
        "f": "json",
    })
    rows = [feature["attributes"] for feature in data["features"]]
    out.write_text(json.dumps(rows))
    return len(rows)


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    root = Path(sys.argv[1])
    root.mkdir(parents=True, exist_ok=True)
    print(fetch_crossings(root / "crossings"), "crossings")
    print(fetch_intermodal(root / "intermodal.json"), "intermodal terminals")


if __name__ == "__main__":
    main()
