// Rail graph built from OpenStreetMap ways (offline only).
// Nodes are OSM nodes shared between ways; edges are consecutive node pairs.
import { execFileSync, spawn } from 'node:child_process';
import readline from 'node:readline';
import { type LonLat, haversine, projectOnSegment } from '../geo/geo.ts';

export interface RailWay { id: number; tags: Record<string, string>; nodes: number[]; coords: LonLat[] }

/** Way types trains in scope run on. Light rail, subway, and dead lines are excluded. */
export function isPassengerTrack(tags: Record<string, string>): boolean {
  return tags.railway === 'rail' || tags.railway === 'narrow_gauge';
}

/** Multiplier on edge length when routing: prefer running lines over yards and sidings. */
export function edgeCost(tags: Record<string, string>): number {
  switch (tags.service) {
    case 'yard': return 4;
    case 'spur': return 3;
    case 'siding': return 1.6;
    case 'crossover': return 1.3;
  }
  if (tags.usage === 'industrial') return 2;
  if (tags.usage === 'tourism' || tags.usage === 'military') return 3;
  return 1;
}

function unescapeOpl(s: string): string {
  return s.replace(/%([0-9a-fA-F]+)%/g, (_, h) => String.fromCodePoint(parseInt(h, 16)));
}

/** Parse one OPL line produced by `osmium add-locations-to-ways -f opl`. */
export function parseOplWay(line: string): RailWay | null {
  if (!line.startsWith('w')) return null;
  const fields = line.split(' ');
  const id = Number(fields[0].slice(1));
  const tags: Record<string, string> = {};
  const nodes: number[] = [];
  const coords: LonLat[] = [];
  for (const f of fields) {
    if (f.startsWith('T') && f.length > 1) {
      for (const kv of f.slice(1).split(',')) {
        const eq = kv.indexOf('=');
        if (eq > 0) tags[unescapeOpl(kv.slice(0, eq))] = unescapeOpl(kv.slice(eq + 1));
      }
    } else if (f.startsWith('N') && f.length > 1) {
      for (const n of f.slice(1).split(',')) {
        const m = /^n(\d+)x(-?[\d.]+)y(-?[\d.]+)$/.exec(n);
        if (!m) continue; // node without location (outside extract)
        nodes.push(Number(m[1]));
        coords.push([Number(m[2]), Number(m[3])]);
      }
    }
  }
  return { id, tags, nodes, coords };
}

export async function readRailWays(pbfPath: string): Promise<RailWay[]> {
  execFileSync('osmium', ['--version'], { stdio: 'ignore' });
  const child = spawn('osmium', ['add-locations-to-ways', pbfPath, '-f', 'opl', '-o', '-', '--ignore-missing-nodes'],
    { stdio: ['ignore', 'pipe', 'inherit'], env: { ...process.env, OSMIUM_POOL_THREADS: '1' } });
  const ways: RailWay[] = [];
  for await (const line of readline.createInterface({ input: child.stdout })) {
    const w = parseOplWay(line);
    if (w && isPassengerTrack(w.tags) && w.nodes.length >= 2) ways.push(w);
  }
  return ways;
}

const CELL = 0.002; // degrees, ~220 m lat / ~165 m lon at 41N

/**
 * Undirected graph in compressed-sparse-row form plus a grid index over segments.
 * Segment k joins node segA[k] to node segB[k].
 */
export class RailGraph {
  lon: Float64Array; lat: Float64Array;
  segA: Int32Array; segB: Int32Array; segLen: Float64Array; segCost: Float64Array; segWay: Int32Array;
  // adjacency: for node i, edges adjStart[i]..adjStart[i+1] list (neighbor, segment)
  adjStart: Int32Array; adjNode: Int32Array; adjSeg: Int32Array;
  grid = new Map<number, number[]>();
  wayIds: number[];

  constructor(ways: RailWay[]) {
    const index = new Map<number, number>();
    const lon: number[] = [], lat: number[] = [];
    const sa: number[] = [], sb: number[] = [], sl: number[] = [], sc: number[] = [], sw: number[] = [];
    this.wayIds = ways.map((w) => w.id);
    ways.forEach((w, wi) => {
      const cost = edgeCost(w.tags);
      let prev = -1;
      for (let i = 0; i < w.nodes.length; i++) {
        let ni = index.get(w.nodes[i]);
        if (ni === undefined) { ni = lon.length; index.set(w.nodes[i], ni); lon.push(w.coords[i][0]); lat.push(w.coords[i][1]); }
        if (prev >= 0 && prev !== ni) {
          sa.push(prev); sb.push(ni); sw.push(wi); sc.push(cost);
          sl.push(haversine([lon[prev], lat[prev]], [lon[ni], lat[ni]]));
        }
        prev = ni;
      }
    });
    this.lon = Float64Array.from(lon); this.lat = Float64Array.from(lat);
    this.segA = Int32Array.from(sa); this.segB = Int32Array.from(sb);
    this.segLen = Float64Array.from(sl); this.segCost = Float64Array.from(sc); this.segWay = Int32Array.from(sw);

    const deg = new Int32Array(lon.length + 1);
    for (let k = 0; k < sa.length; k++) { deg[sa[k] + 1]++; deg[sb[k] + 1]++; }
    for (let i = 1; i < deg.length; i++) deg[i] += deg[i - 1];
    this.adjStart = deg.slice();
    this.adjNode = new Int32Array(sa.length * 2); this.adjSeg = new Int32Array(sa.length * 2);
    const fill = deg.slice();
    for (let k = 0; k < sa.length; k++) {
      this.adjNode[fill[sa[k]]] = sb[k]; this.adjSeg[fill[sa[k]]++] = k;
      this.adjNode[fill[sb[k]]] = sa[k]; this.adjSeg[fill[sb[k]]++] = k;
    }

    for (let k = 0; k < sa.length; k++) {
      const x0 = Math.floor(Math.min(lon[sa[k]], lon[sb[k]]) / CELL), x1 = Math.floor(Math.max(lon[sa[k]], lon[sb[k]]) / CELL);
      const y0 = Math.floor(Math.min(lat[sa[k]], lat[sb[k]]) / CELL), y1 = Math.floor(Math.max(lat[sa[k]], lat[sb[k]]) / CELL);
      for (let x = x0; x <= x1; x++) for (let y = y0; y <= y1; y++) {
        const key = x * 100000 + y;
        let cell = this.grid.get(key);
        if (!cell) { cell = []; this.grid.set(key, cell); }
        cell.push(k);
      }
    }
  }

  get nodeCount(): number { return this.lon.length; }
  get segmentCount(): number { return this.segA.length; }
  node(i: number): LonLat { return [this.lon[i], this.lat[i]]; }

  /** Segments within `radius` metres of p, nearest first, at most one candidate per way. */
  nearSegments(p: LonLat, radius: number, max = 8): { seg: number; t: number; dist: number; point: LonLat }[] {
    const r = Math.ceil(radius / 150);
    const cx = Math.floor(p[0] / CELL), cy = Math.floor(p[1] / CELL);
    const seen = new Set<number>();
    const found: { seg: number; t: number; dist: number; point: LonLat }[] = [];
    for (let x = cx - r; x <= cx + r; x++) for (let y = cy - r; y <= cy + r; y++) {
      for (const k of this.grid.get(x * 100000 + y) ?? []) {
        if (seen.has(k)) continue; seen.add(k);
        const pr = projectOnSegment(p, this.node(this.segA[k]), this.node(this.segB[k]));
        if (pr.dist <= radius) found.push({ seg: k, ...pr });
      }
    }
    found.sort((a, b) => a.dist - b.dist);
    const perWay = new Set<number>();
    const out = [];
    for (const f of found) {
      if (perWay.has(this.segWay[f.seg])) continue;
      perWay.add(this.segWay[f.seg]);
      out.push(f);
      if (out.length >= max) break;
    }
    return out;
  }
}
