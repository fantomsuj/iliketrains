// Offline: snap every timetable route onto OpenStreetMap track and store the result.
//
//   node src/build/build-routes.ts [--rail ../tiles/dist/rail.osm.pbf] [--feeds amtrak,lirr,mnr,njt]
//
// Output: data/derived/routes.json. Its geometry is derived from OpenStreetMap and is
// therefore ODbL-licensed; it is kept apart from the timetable data on purpose.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { type LonLat, Polyline, encodePolyline, simplify } from '../geo/geo.ts';
import { GtfsFeed } from '../gtfs.ts';
import { inRegion } from '../region.ts';
import { RailGraph, readRailWays } from './railgraph.ts';
import { DEFAULT_MATCH, Router, mapMatch } from './mapmatch.ts';
import { FEEDS, type RoutesFile, type ShapeRecord, type PatternRecord, type OverviewLine } from '../routes.ts';

const ROOT = path.resolve(import.meta.dirname, '../..');
const args = process.argv.slice(2);
const arg = (k: string, d: string) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const railPath = arg('--rail', path.resolve(ROOT, '../tiles/dist/rail.osm.pbf'));
const feedIds = arg('--feeds', FEEDS.join(',')).split(',');
const outPath = arg('--out', path.join(ROOT, 'data/derived/routes.json'));

/**
 * Route between consecutive stations on the graph (for trips that have no shape).
 * Stations are the only observations, so this is the same HMM with sparse points: candidates
 * on tracks near each station, transitions by shortest track path, no resampling in between.
 */
export const STOPS_MATCH = { ...DEFAULT_MATCH, sampleStep: 1e9, radius: 300, wideRadius: 1200, sigma: 120, beta: 3000, maxCandidates: 8 };
function routeThroughStops(g: RailGraph, router: Router, stops: LonLat[]) {
  return mapMatch(g, stops, { ...STOPS_MATCH, inScope: inRegion }, router);
}

function geometryKey(coords: LonLat[]): string {
  const step = Math.max(1, Math.floor(coords.length / 50));
  let s = `${coords.length}`;
  for (let i = 0; i < coords.length; i += step) s += `|${coords[i][0].toFixed(3)},${coords[i][1].toFixed(3)}`;
  const last = coords[coords.length - 1];
  return s + `|${last[0].toFixed(3)},${last[1].toFixed(3)}`;
}

/** Distance of each stop along the line, forced to be non-decreasing. */
export function stopDistances(line: Polyline, stops: LonLat[]): { dist: number[]; maxOffset: number } {
  const dist: number[] = []; let minD = 0, maxOffset = 0;
  for (const s of stops) {
    // look ahead a bounded window so a later pass through the same area is not picked
    let r = line.project(s, minD, minD + 150000);
    if (r.offset > 2000) r = line.project(s, minD);
    if (!Number.isFinite(r.offset)) r = { d: minD, offset: 0 }; // nothing ahead: pin to the previous stop
    dist.push(r.d); minD = r.d; maxOffset = Math.max(maxOffset, r.offset);
  }
  return { dist, maxOffset };
}

async function main() {
  console.log(`reading rail ways from ${railPath}`);
  let t0 = Date.now();
  const ways = await readRailWays(railPath);
  const g = new RailGraph(ways);
  console.log(`graph: ${g.nodeCount} nodes, ${g.segmentCount} segments (${Date.now() - t0} ms)`);
  const router = new Router(g);

  const out: RoutesFile = out_ = { generatedAt: new Date().toISOString(), license: 'Geometry (c) OpenStreetMap contributors, ODbL 1.0',
    railSource: path.basename(railPath), overview: [], shapes: {}, patterns: {} };

  for (const feedId of feedIds) {
    t0 = Date.now();
    const feed = new GtfsFeed(feedId, path.join(ROOT, 'data/gtfs', feedId));
    const rawShapes = feed.loadShapes();
    const patterns: Record<string, PatternRecord> = {};
    const shapeByGeom = new Map<string, string>(); // geometry key -> shape record key
    const shapeAlias = new Map<string, string>();  // gtfs shape id -> shape record key
    let matched = 0, reused = 0, synthesized = 0, reversed = 0;

    const tripsByPattern = new Map<string, { shapeId: string; stops: string[] }>();
    for (const t of feed.trips.values()) {
      const route = feed.routes.get(t.routeId);
      if (route && route.type !== 2) continue; // rail only (drops buses, light rail)
      if (t.stopIds.length < 2) continue;
      const stops = t.stopIds.map((s) => feed.stationOf(s));
      // long-distance trains that never enter the region need no geometry
      if (!stops.some((s) => { const c = feed.stops.get(s)?.lonlat; return c && inRegion(c); })) continue;
      const key = `${t.shapeId}|${stops.join(',')}`;
      if (!tripsByPattern.has(key)) tripsByPattern.set(key, { shapeId: t.shapeId, stops });
    }

    for (const [pkey, p] of tripsByPattern) {
      const stopCoords = p.stops.map((s) => feed.stops.get(s)?.lonlat).filter((x): x is LonLat => !!x);
      let shapeKey: string;
      const raw = p.shapeId ? rawShapes.get(p.shapeId) : undefined;
      if (raw && raw.length >= 2) {
        if (shapeAlias.has(p.shapeId)) shapeKey = shapeAlias.get(p.shapeId)!;
        else {
          const gk = geometryKey(raw);
          if (shapeByGeom.has(gk)) { shapeKey = shapeByGeom.get(gk)!; reused++; }
          else {
            shapeKey = `${feedId}:${p.shapeId}`;
            const m = mapMatch(g, raw, { ...DEFAULT_MATCH, inScope: inRegion }, router);
            out.shapes[shapeKey] = record(feedId, p.shapeId, m.coords, m.matchedFraction, m.meanOffset, m.breaks);
            shapeByGeom.set(gk, shapeKey); matched++;
          }
          shapeAlias.set(p.shapeId, shapeKey);
        }
      } else {
        shapeKey = `${feedId}:stops:${p.stops.join('-')}`;
        if (!out.shapes[shapeKey]) {
          const m = routeThroughStops(g, router, stopCoords);
          out.shapes[shapeKey] = record(feedId, '', m.coords, m.matchedFraction, m.meanOffset, m.breaks);
          synthesized++;
        }
      }
      let line = new Polyline(decodeFor(out.shapes[shapeKey]));
      // Some feeds (Amtrak) share one shape between both directions: run it the trip's way.
      if (stopCoords.length >= 2 && line.project(stopCoords[0]).d > line.project(stopCoords[stopCoords.length - 1]).d + 1000) {
        const rev = `${shapeKey}:rev`;
        if (!out.shapes[rev]) {
          const src = out.shapes[shapeKey];
          out.shapes[rev] = record(feedId, src.shapeId, decodeFor(src).slice().reverse(), src.matchedFraction, src.meanOffset, src.breaks);
          reversed++;
        }
        shapeKey = rev; line = new Polyline(decodeFor(out.shapes[rev]));
      }
      const { dist, maxOffset } = stopDistances(line, stopCoords);
      patterns[pkey] = { shape: shapeKey, stops: p.stops, dist: dist.map((d) => Math.round(d)), maxStopOffset: Math.round(maxOffset) };
    }
    out.patterns[feedId] = patterns;
    out.overview.push(...overviewLines(feed, patterns));
    const recs = Object.values(out.shapes).filter((s) => s.feed === feedId && !Number.isNaN(s.matchedFraction));
    const avg = recs.reduce((a, s) => a + s.matchedFraction, 0) / Math.max(1, recs.length);
    console.log(`${feedId}: ${tripsByPattern.size} stop patterns, ${matched} shapes matched, ${reused} duplicate shapes reused, ` +
      `${synthesized} built from stops, ${reversed} reversed for direction; mean matched ${(avg * 100).toFixed(1)}% (${Date.now() - t0} ms)`);
  }
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, JSON.stringify(out));
  console.log(`wrote ${outPath} (${(fs.statSync(outPath).size / 1e6).toFixed(1)} MB)`);
}

/**
 * Route lines for the network map: per route, the longest geometry first, then any other
 * geometry that adds more than 15% new track. Coverage is checked on a ~50 m grid.
 */
function overviewLines(feed: GtfsFeed, patterns: Record<string, PatternRecord>): OverviewLine[] {
  const routeOfShape = new Map<string, string>();
  for (const t of feed.trips.values()) if (t.shapeId && !routeOfShape.has(t.shapeId)) routeOfShape.set(t.shapeId, t.routeId);
  const byRoute = new Map<string, Set<string>>();
  for (const [k, p] of Object.entries(patterns)) {
    const routeId = routeOfShape.get(k.split('|')[0]) ?? '';
    const r = byRoute.get(routeId) ?? new Set(); r.add(p.shape); byRoute.set(routeId, r);
  }
  const cell = (c: LonLat) => `${Math.round(c[0] / 0.0006)},${Math.round(c[1] / 0.00045)}`;
  const out: OverviewLine[] = [];
  for (const [routeId, keys] of byRoute) {
    const r = feed.routes.get(routeId);
    const color = feed.id === 'amtrak' ? '#4a90d9' : `#${r?.color || '9aa5b1'}`;
    const covered = new Set<string>();
    const sorted = [...keys].filter((k) => !k.endsWith(':rev')).sort((a, b) => out_.shapes[b].lengthM - out_.shapes[a].lengthM);
    for (const k of sorted) {
      const line = new Polyline(decodeFor(out_.shapes[k]));
      const cells: string[] = [];
      for (let d = 0; d <= line.length; d += 40) cells.push(cell(line.pointAt(d).lonlat));
      const novel = cells.filter((c) => !covered.has(c)).length / Math.max(1, cells.length);
      if (novel > 0.15) {
        out.push({ key: k, operator: feed.id, route: r?.longName || r?.shortName || routeId, color });
        // mark the cell and its neighbours so parallel copies a few metres apart count as covered
        for (const c of cells) { const [x, y] = c.split(',').map(Number); for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) covered.add(`${x + dx},${y + dy}`); }
      }
    }
  }
  return out;
}

let out_: RoutesFile;
const decoded = new Map<string, LonLat[]>();
function record(feed: string, shapeId: string, coords: LonLat[], matchedFraction: number, meanOffset: number, breaks: number): ShapeRecord {
  const simple = simplify(coords, 2);
  const rec: ShapeRecord = { feed, shapeId, polyline: encodePolyline(simple), lengthM: Math.round(new Polyline(simple).length),
    matchedFraction: Math.round(matchedFraction * 1000) / 1000, meanOffset: Math.round(meanOffset * 10) / 10, breaks };
  decoded.set(rec.polyline, simple);
  return rec;
}
function decodeFor(r: ShapeRecord): LonLat[] { return decoded.get(r.polyline)!; }

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch((e) => { console.error(e); process.exit(1); });
