#!/usr/bin/env python3
"""Build the bundled route atlas from public rail data.

Inputs (download first, see README in this folder):
  NTAD_North_American_Rail_Network_Lines.geojson   BTS / FRA, ~300k track segments
  amtrak_routes .shp/.dbf                          BTS NTAD Amtrak Routes (route guide lines)

Output: a compact JSON file the app decodes at launch.

    python3 scripts/route_atlas/build.py NARN.geojson amtrak_routes.shp "I Like Trains/Data/route-atlas.json"
"""
from __future__ import annotations

import collections
import heapq
import json
import math
import sys
from pathlib import Path

import networkx as nx
import numpy as np
import shapefile
from shapely import STRtree
from shapely.geometry import LineString, Point, shape

sys.path.insert(0, str(Path(__file__).parent))
from cities import CITIES  # noqa: E402
from routes import RAILROADS, ROUTES  # noqa: E402

USABLE_NET = {"M": 1.0, "O": 1.4, "S": 1.3, "Y": 2.5, "I": 3.0, "T": 1.6, "F": 1.0}
SIMPLIFY_DEG = 0.004  # ~400 m; plenty for a national/regional map view
CITY_STOP_KM = 9.0


def haversine_km(a, b):
    lon1, lat1, lon2, lat2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((lat2 - lat1) / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(h))


def encode_polyline(coords):
    """Google encoded polyline (precision 5) of (lon, lat) pairs."""
    out, prev_lat, prev_lon = [], 0, 0
    for lon, lat in coords:
        ilat, ilon = round(lat * 1e5), round(lon * 1e5)
        for delta in (ilat - prev_lat, ilon - prev_lon):
            v = ~(delta << 1) if delta < 0 else delta << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        prev_lat, prev_lon = ilat, ilon
    return "".join(out)


def simplify(coords):
    if len(coords) < 3:
        return coords
    s = LineString(coords).simplify(SIMPLIFY_DEG, preserve_topology=False)
    return [tuple(c) for c in s.coords]


def bearing_word(a, b):
    dx = (b[0] - a[0]) * math.cos(math.radians((a[1] + b[1]) / 2))
    dy = b[1] - a[1]
    angle = (math.degrees(math.atan2(dx, dy)) + 360) % 360
    return ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][int((angle + 22.5) // 45) % 8]


def load_network(path):
    import pickle
    cache = Path(path).with_suffix(".atlas-cache.pkl")
    if cache.exists():
        return pickle.load(open(cache, "rb"))
    result = _load_network(path)
    pickle.dump(result, open(cache, "wb"))
    return result


def _load_network(path):
    print("reading", path, file=sys.stderr)
    data = json.load(open(path))
    edges = []
    for f in data["features"]:
        p, g = f["properties"], f["geometry"]
        if not g or p["NET"] not in USABLE_NET:
            continue
        coords = g["coordinates"] if g["type"] == "LineString" else [c for part in g["coordinates"] for c in part]
        if len(coords) < 2:
            continue
        marks = {p[k] for k in ("RROWNER1", "RROWNER2", "RROWNER3") if p[k]}
        marks |= {p[f"TRKRGHTS{i}"] for i in range(1, 10) if p[f"TRKRGHTS{i}"]}
        edges.append({
            "a": p["FRFRANODE"], "b": p["TOFRANODE"], "miles": p["MILES"] or 0.0, "net": p["NET"],
            "passenger": bool(p["PASSNGR"]) or "AMTK" in marks or "VIA" in marks,
            "marks": marks, "subdiv": p["SUBDIV"], "coords": [tuple(c[:2]) for c in coords],
        })
    del data
    nodes = {}
    for e in edges:
        nodes.setdefault(e["a"], e["coords"][0])
        nodes.setdefault(e["b"], e["coords"][-1])
    print(len(edges), "usable segments", file=sys.stderr)
    return edges, nodes


def build_graph(edges, keep, cost):
    g = nx.Graph()
    for i, e in enumerate(edges):
        if not keep(e) or e["a"] == e["b"]:
            continue
        w = cost(i, e)
        if g.has_edge(e["a"], e["b"]) and g[e["a"]][e["b"]]["w"] <= w:
            continue
        g.add_edge(e["a"], e["b"], w=w, i=i)
    return g


class Snapper:
    """Nearest-node lookup restricted to a set of candidate nodes."""

    def __init__(self, nodes, candidates, preferred=frozenset()):
        self.ids = list(candidates)
        xy = np.array([nodes[n] for n in self.ids]) if self.ids else np.zeros((0, 2))
        self.lon, self.lat = xy[:, 0], xy[:, 1]
        self.penalty = np.array([0.0 if n in preferred else 3.0 for n in self.ids]) if preferred else np.zeros(len(self.ids))

    def __call__(self, point, max_km):
        if not self.ids:
            return None
        kx = 111.32 * math.cos(math.radians(point[1]))
        d = np.hypot((self.lon - point[0]) * kx, (self.lat - point[1]) * 110.57)
        score = d + self.penalty
        i = int(np.argmin(score))
        return self.ids[i] if d[i] <= max_km else None


def big_component_nodes(g, min_nodes):
    keep = set()
    for comp in nx.connected_components(g):
        if len(comp) >= min_nodes:
            keep |= comp
    return keep


def path_geometry(edges, nodes, g, path):
    coords, miles, subdivs = [nodes[path[0]]], 0.0, collections.Counter()
    for u, v in zip(path, path[1:]):
        e = edges[g[u][v]["i"]]
        seg = e["coords"] if e["a"] == u else list(reversed(e["coords"]))
        coords.extend(seg[1:])
        miles += e["miles"]
        if e["subdiv"]:
            subdivs[e["subdiv"]] += e["miles"]
    return coords, miles, subdivs


def city_point(cid):
    c = CITIES[cid]
    return (c[3], c[2])


# ---------------------------------------------------------------- passenger

def build_passenger(edges, nodes, guide_path):
    reader = shapefile.Reader(str(guide_path))
    guides = {}
    for sr in reader.iterShapeRecords():
        guides[sr.record["name"].strip()] = shape(sr.shape.__geo_interface__)
    mids = [Point(e["coords"][len(e["coords"]) // 2]) for e in edges]
    tree = STRtree(mids)
    base = build_graph(edges, lambda e: True, lambda i, e: 1.0)
    base = base.subgraph(max(nx.connected_components(base), key=len)).copy()
    passenger_node = {n for u, v, d in base.edges(data=True) if edges[d["i"]]["passenger"] for n in (u, v)}
    snapper = Snapper(nodes, base.nodes, passenger_node)
    out = []
    for rid, name, operator, kind, guide_names, stops in ROUTES:
        near = set()
        for gname in guide_names:
            gg = guides.get(gname)
            if gg is None:
                raise SystemExit(f"missing guide layer {gname!r}")
            near.update(int(i) for i in tree.query(gg.buffer(0.02)))

        def cost(i, e, near=near, guided=bool(guide_names)):
            f = USABLE_NET[e["net"]] * (1.0 if e["passenger"] else 4.0)
            if guided and i not in near:
                f *= 3.0
            return max(e["miles"], 0.01) * f

        g = nx.Graph()
        for u, v, d in base.edges(data=True):
            g.add_edge(u, v, w=cost(d["i"], edges[d["i"]]), i=d["i"])
        snapped = [snapper(city_point(c), 15) for c in stops]
        missing = [c for c, n in zip(stops, snapped) if n is None]
        if missing:
            raise SystemExit(f"{rid}: could not snap {missing}")
        full = [snapped[0]]
        for a, b in zip(snapped, snapped[1:]):
            full.extend(nx.shortest_path(g, a, b, weight="w")[1:])
        coords, miles, _ = path_geometry(edges, nodes, g, full)
        # cumulative miles per vertex, scaled to official segment mileage
        cum = [0.0]
        for p, q in zip(coords, coords[1:]):
            cum.append(cum[-1] + haversine_km(p, q))
        scale = miles / cum[-1] if cum[-1] else 0
        served = []
        arr = np.array(coords)
        for cid in CITIES:
            pt = city_point(cid)
            kx = 111.32 * math.cos(math.radians(pt[1]))
            d = np.hypot((arr[:, 0] - pt[0]) * kx, (arr[:, 1] - pt[1]) * 110.57)
            best_i = int(np.argmin(d))
            if d[best_i] <= CITY_STOP_KM or cid in stops:
                served.append((cum[best_i] * scale, cid))
        served.sort()
        out.append({
            "id": rid, "name": name, "operator": operator, "kind": kind,
            "from": stops[0], "to": stops[-1], "miles": round(miles),
            "stops": [{"city": cid, "mile": round(m)} for m, cid in served],
            "path": encode_polyline(simplify(coords)),
        })
        print(f"  {name}: {miles:.0f} mi, {len(served)} cities", file=sys.stderr)
    return out


# ---------------------------------------------------------------- freight

def build_freight(edges, nodes):
    """Per railroad: a shared set of track pieces, plus one route tree per hub that references them.

    Every hub's tree overlaps heavily with its neighbours' trees, so geometry is stored once per
    railroad as pieces between junctions, and tree branches are lists of signed piece indexes
    (k + 1 = piece k as stored, -(k + 1) = piece k reversed).
    """
    hubs = [cid for cid, c in CITIES.items() if c[4]]
    tracks, networks, pairs = [], [], []
    for rr, codes in RAILROADS:
        codes = set(codes)
        g = build_graph(
            edges,
            lambda e: bool(e["marks"] & codes),
            lambda i, e: max(e["miles"], 0.01) * USABLE_NET[e["net"]],
        )
        main_nodes = {n for u, v, d in g.edges(data=True) if edges[d["i"]]["net"] == "M" for n in (u, v)}
        snapper = Snapper(nodes, big_component_nodes(g, 500), main_nodes)
        hub_node = {}
        for h in hubs:
            n = snapper(city_point(h), 25)
            if n is not None and n not in hub_node.values():
                hub_node[h] = n
        print(f"{rr}: {g.number_of_edges()} segments, {len(hub_node)} hubs", file=sys.stderr)

        trees = []  # (hub, [(parent, weight, ends, node_chain)])
        union = nx.Graph()
        for h, src in hub_node.items():
            _, paths = nx.single_source_dijkstra(g, src, weight="w")
            targets = [t for t, n in hub_node.items() if t != h and n in paths and n != src]
            if not targets:
                continue
            children = collections.defaultdict(set)
            count = collections.Counter()
            ends = collections.defaultdict(list)
            for t in targets:
                p = paths[hub_node[t]]
                ends[p[-1]].append(t)
                for u, v in zip(p, p[1:]):
                    children[u].add(v)
                    count[(u, v)] += 1
                    union.add_edge(u, v)
                if h < t:
                    _, miles, subdivs = path_geometry(edges, nodes, g, p)
                    via = [s.title() for s, _ in subdivs.most_common(3)]
                    pairs.append({"railroad": rr, "from": h, "to": t, "miles": round(miles), "via": via})
            branches = []
            stack = [(src, -1)]
            while stack:
                start, parent = stack.pop()
                for nxt in sorted(children[start]):
                    chain = [start, nxt]
                    while len(children[chain[-1]]) == 1 and chain[-1] not in ends:
                        chain.append(next(iter(children[chain[-1]])))
                    branches.append((parent, count[(chain[0], chain[1])], ends.get(chain[-1], []), chain))
                    stack.append((chain[-1], len(branches) - 1))
            trees.append((h, branches))

        # Split the union of all trees into pieces between junctions / hubs / branch points.
        split = {n for n in union.nodes if union.degree(n) != 2} | set(hub_node.values())
        for _, branches in trees:
            for _, _, _, chain in branches:
                split.add(chain[0])
                split.add(chain[-1])
        piece_of = {}  # (u, v) -> signed piece ref for the first edge of a piece walked u->v
        pieces = []
        for u in split:
            for v in union.neighbors(u):
                if (u, v) in piece_of:
                    continue
                chain = [u, v]
                while chain[-1] not in split:
                    nxt = [w for w in union.neighbors(chain[-1]) if w != chain[-2]]
                    chain.append(nxt[0])
                coords, _, _ = path_geometry(edges, nodes, g, chain)
                pieces.append(encode_polyline(simplify(coords)))
                k = len(pieces)
                piece_of[(chain[0], chain[1])] = k
                piece_of[(chain[-1], chain[-2])] = -k
        tracks.append({"railroad": rr, "pieces": pieces})
        for h, branches in trees:
            out = []
            for parent, weight, ends, chain in branches:
                refs = []
                for u, v in zip(chain, chain[1:]):
                    if u in split and u != chain[-1]:
                        refs.append(piece_of[(u, v)])
                out.append({"parent": parent, "weight": weight, "ends": ends, "pieces": refs})
            networks.append({"railroad": rr, "hub": h, "branches": out})
    return tracks, networks, pairs


def main():
    narn, guide, out_path = sys.argv[1:4]
    edges, nodes = load_network(narn)
    passenger = build_passenger(edges, nodes, Path(guide))
    tracks, networks, pairs = build_freight(edges, nodes)
    used = {s["city"] for r in passenger for s in r["stops"]} | {n["hub"] for n in networks}
    atlas = {
        "version": 2,
        "sources": [
            "North American Rail Network Lines, Bureau of Transportation Statistics NTAD (2025 release)",
            "Amtrak Routes, Bureau of Transportation Statistics NTAD (route guide lines)",
        ],
        "cities": [
            {"id": cid, "name": c[0], "region": c[1], "lat": c[2], "lon": c[3], "freightHub": c[4]}
            for cid, c in CITIES.items() if cid in used
        ],
        "passengerRoutes": passenger,
        "freightTrack": tracks,
        "freightNetworks": networks,
        "freightPairs": pairs,
    }
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    Path(out_path).write_text(json.dumps(atlas, separators=(",", ":"), ensure_ascii=False))
    print("wrote", out_path, Path(out_path).stat().st_size // 1024, "KB", file=sys.stderr)


if __name__ == "__main__":
    main()
