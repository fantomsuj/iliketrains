// Route geometry produced offline by build/build-routes.ts and loaded by the live server.
import fs from 'node:fs';
import { Polyline, decodePolyline } from './geo/geo.ts';

export const FEEDS = ['amtrak', 'lirr', 'mnr', 'njt'] as const;
export type FeedId = (typeof FEEDS)[number];

export interface ShapeRecord {
  feed: string; shapeId: string; polyline: string; lengthM: number;
  /** share of the timetable shape that landed on OSM track; NaN when synthesised from stops */
  matchedFraction: number; meanOffset: number; breaks: number;
}
export interface PatternRecord { shape: string; stops: string[]; dist: number[]; maxStopOffset: number }
export interface OverviewLine { key: string; operator: string; route: string; color: string }
export interface RoutesFile {
  generatedAt: string; license: string; railSource: string;
  /** Distinct route lines for the network map (one per geometry per route), computed offline. */
  overview: OverviewLine[];
  shapes: Record<string, ShapeRecord>;
  patterns: Record<string, Record<string, PatternRecord>>;
}

/** Share of `want` stations found in `have` in the same order (greedy). */
export function orderedCoverage(want: string[], have: string[]): number {
  if (!want.length) return 0;
  let j = 0, hits = 0;
  for (const w of want) {
    const k = have.indexOf(w, j);
    if (k >= 0) { hits++; j = k + 1; }
  }
  return hits / want.length;
}

export class RouteIndex {
  private lines = new Map<string, Polyline>();
  readonly file: RoutesFile;
  constructor(file: RoutesFile) { this.file = file; }
  static load(p: string): RouteIndex { return new RouteIndex(JSON.parse(fs.readFileSync(p, 'utf8'))); }

  line(shapeKey: string): Polyline | undefined {
    let l = this.lines.get(shapeKey);
    if (!l) {
      const r = this.file.shapes[shapeKey];
      if (!r) return undefined;
      l = new Polyline(decodePolyline(r.polyline));
      this.lines.set(shapeKey, l);
    }
    return l;
  }

  pattern(feed: string, shapeId: string, stations: string[]): PatternRecord | undefined {
    return this.file.patterns[feed]?.[`${shapeId}|${stations.join(',')}`];
  }

  private byStation = new Map<string, Map<string, PatternRecord[]>>();
  /**
   * Pattern of `feed` that covers the most of `stations` in order (ties: the shortest geometry).
   * Used when the timetable trip for a live train is missing or runs the other way.
   */
  bestCoverage(feed: string, stations: string[]): { pattern: PatternRecord; coverage: number } | undefined {
    let idx = this.byStation.get(feed);
    if (!idx) {
      idx = new Map();
      for (const p of Object.values(this.file.patterns[feed] ?? {})) for (const s of new Set(p.stops)) idx.set(s, [...(idx.get(s) ?? []), p]);
      this.byStation.set(feed, idx);
    }
    const cands = new Set<PatternRecord>();
    for (const s of [stations[0], stations[stations.length - 1], stations[stations.length >> 1]]) for (const p of idx.get(s) ?? []) cands.add(p);
    let best: { pattern: PatternRecord; coverage: number } | undefined;
    for (const p of cands) {
      const c = orderedCoverage(stations, p.stops);
      const len = this.file.shapes[p.shape]?.lengthM ?? Infinity;
      if (!best || c > best.coverage || (c === best.coverage && len < (this.file.shapes[best.pattern.shape]?.lengthM ?? Infinity))) best = { pattern: p, coverage: c };
    }
    return best;
  }
}
