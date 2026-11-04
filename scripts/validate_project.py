#!/usr/bin/env python3
"""Read-only structural validation for the I Like Trains Xcode project."""

from __future__ import annotations

import json
import re
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]
PBX_PATH = ROOT / "I Like Trains.xcodeproj" / "project.pbxproj"
SCHEME_PATH = ROOT / "I Like Trains.xcodeproj" / "xcshareddata" / "xcschemes" / "I Like Trains.xcscheme"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def main() -> None:
    required = [
        PBX_PATH,
        SCHEME_PATH,
        ROOT / "I Like Trains" / "I_Like_TrainsApp.swift",
        ROOT / "I Like Trains" / "Views" / "RailMapView.swift",
        ROOT / "I Like TrainsTests" / "MockRailDataServiceTests.swift",
        ROOT / "I Like TrainsTests" / "RailMapViewModelTests.swift",
        ROOT / "README.md",
    ]
    missing = [str(path.relative_to(ROOT)) for path in required if not path.exists()]
    if missing:
        fail(f"missing required files: {', '.join(missing)}")

    pbx = PBX_PATH.read_text(encoding="utf-8")
    if pbx.count("IPHONEOS_DEPLOYMENT_TARGET = 17.0;") < 6:
        fail("every project/target configuration must target iOS 17.0")
    if "XCRemoteSwiftPackageReference" in pbx:
        fail("third-party Swift package reference found")
    if "INFOPLIST_KEY_NSLocationWhenInUseUsageDescription" not in pbx:
        fail("location usage description is missing")
    if pbx.count("PRODUCT_MODULE_NAME = ILikeTrainsData;") != 2:
        fail("Xcode app module must match the SwiftPM module imported by tests")

    definitions = re.findall(
        r"^\s*([A-Z0-9]{24})(?: /\*.*?\*/)? = \{\n\s*isa =",
        pbx,
        re.MULTILINE,
    )
    if len(definitions) != len(set(definitions)):
        fail("duplicate project object definitions found")

    app_sources = sorted((ROOT / "I Like Trains").rglob("*.swift"))
    test_sources = sorted((ROOT / "I Like TrainsTests").glob("*.swift"))
    for source in app_sources + test_sources:
        marker = f"{source.name} in Sources"
        if pbx.count(marker) != 2:
            fail(f"{source.name} does not have exactly one build-file and one sources-phase entry")

    placeholder = re.compile(r"\b(?:TODO|TBD|FIXME)\b")
    for source in app_sources + test_sources:
        if placeholder.search(source.read_text(encoding="utf-8")):
            fail(f"placeholder marker found in {source.relative_to(ROOT)}")

    for json_path in (ROOT / "I Like Trains" / "Resources").rglob("Contents.json"):
        try:
            json.loads(json_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as error:
            fail(f"invalid asset catalog JSON in {json_path.relative_to(ROOT)}: {error}")

    icon = ROOT / "I Like Trains" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    if not icon.exists() or icon.stat().st_size < 1_000:
        fail("1024-point app icon is missing or empty")

    try:
        ElementTree.parse(SCHEME_PATH)
    except ElementTree.ParseError as error:
        fail(f"shared scheme is invalid XML: {error}")

    atlas_path = ROOT / "I Like Trains" / "Data" / "route-atlas.json"
    if not atlas_path.exists():
        fail("route atlas data is missing; run scripts/route_atlas/build.py")
    atlas = json.loads(atlas_path.read_text(encoding="utf-8"))
    for key in ("cities", "passengerRoutes", "freightTrack", "freightNetworks", "freightPairs"):
        if not atlas.get(key):
            fail(f"route atlas has no {key}")
    if pbx.count("route-atlas.json in Resources") != 2:
        fail("route-atlas.json must be in the app's Copy Bundle Resources phase")

    tests = "\n".join(path.read_text(encoding="utf-8") for path in test_sources)
    for expected in ("MockRailDataService", "RailMapViewModel", "refresh", "filteredTrains"):
        if expected not in tests:
            fail(f"expected data-layer test coverage marker missing: {expected}")

    print(
        "PASS: project graph, target membership, iOS 17 settings, assets, scheme, "
        f"and {len(app_sources) + len(test_sources)} Swift source files validated"
    )


if __name__ == "__main__":
    main()
