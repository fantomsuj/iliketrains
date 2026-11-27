// Hidden-Markov-model map matching (Newson & Krumm 2009) of a timetable shape onto the rail graph.
//
// States are candidate positions on nearby track segments; emission favours candidates close to the
// shape point, transition favours candidate pairs whose distance along the track matches the
// straight-line distance between the shape points. The best sequence is found with Viterbi and the
// track path between consecutive chosen candidates is stitched into the output polyline.
import { type LonLat, densify, haversine } from '../geo/geo.ts';
import type { RailGraph } from './railgraph.ts';

export interface MatchOptions {
  sampleStep: number;   // metres between resampled shape points
  radius: number;       // candidate search radius, metres
  wideRadius: number;   // retry radius when nothing is within `radius`
  sigma: number;        // emission std-dev, metres
  beta: number;         // transition scale, metres
  maxCandidates: number;
  /** Points this returns false for (outside the mapped region) don't count against matchedFraction. */
  inScope?: (p: LonLat) => boolean;
}

export const DEFAULT_MATCH: MatchOptions = { sampleStep: 80, radius: 60, wideRadius: 200, sigma: 20, beta: 60, maxCandidates: 6 };

interface Cand { seg: number; t: number; dist: number; point: LonLat }

export interface MatchResult {
  coords: LonLat[];
  /** Share of in-scope resampled shape points that ended up on matched track (0..1). */
  matchedFraction: number;
  /** Mean distance from shape point to its chosen track position, metres. */
  meanOffset: number;
  /** Number of places where matching broke and the raw shape was used instead. */
  breaks: number;
}

class MinHeap {
  private k: number[] = []; private v: number[] = [];
  get size() { return this.k.length; }
  push(key: number, val: number) {
    const k = this.k, v = this.v; let i = k.length; k.push(key); v.push(val);
    while (i > 0) { const p = (i - 1) >> 1; if (k[p] <= key) break; k[i] = k[p]; v[i] = v[p]; i = p; }
    k[i] = key; v[i] = val;
  }
  pop(): [number, number] {
    const k = this.k, v = this.v; const top: [number, number] = [k[0], v[0]];
    const lk = k.pop()!, lv = v.pop()!;
    if (k.length) {
      let i = 0; const n = k.length;
      for (;;) {
        let c = 2 * i + 1; if (c >= n) break;
        if (c + 1 < n && k[c + 1] < k[c]) c++;
        if (k[c] >= lk) break;
        k[i] = k[c]; v[i] = v[c]; i = c;
      }
      k[i] = lk; v[i] = lv;
    }
    return top;
  }
}

/** Bounded Dijkstra from a point on a segment. Reuses buffers across calls. */
export class Router {
  private g: RailGraph; private dist: Float64Array; private pred: Int32Array; private touched: number[] = [];
  constructor(g: RailGraph) {
    this.g = g;
    this.dist = new Float64Array(g.nodeCount).fill(Infinity);
    this.pred = new Int32Array(g.nodeCount).fill(-1);
  }

  /** Track cost from `from` to each of `targets` (Infinity when farther than `cutoff`). */
  costs(from: Cand, targets: Cand[], cutoff: number): number[] {
    this.run(from, cutoff);
    return targets.map((to) => this.costTo(from, to));
  }

  private costTo(from: Cand, to: Cand): number {
    const g = this.g;
    const c = g.segCost[to.seg], len = g.segLen[to.seg];
    if (to.seg === from.seg) return Math.abs(to.t - from.t) * len * c;
    return Math.min(this.dist[g.segA[to.seg]] + to.t * len * c, this.dist[g.segB[to.seg]] + (1 - to.t) * len * c);
  }

  /** Node path (as coordinates) from `from` to `to`, including both candidate points. */
  path(from: Cand, to: Cand, cutoff: number): LonLat[] | null {
    const g = this.g;
    if (to.seg === from.seg) return [from.point, to.point];
    this.run(from, cutoff);
    const c = g.segCost[to.seg], len = g.segLen[to.seg];
    const viaA = this.dist[g.segA[to.seg]] + to.t * len * c;
    const viaB = this.dist[g.segB[to.seg]] + (1 - to.t) * len * c;
    if (!Number.isFinite(Math.min(viaA, viaB))) return null;
    let n = viaA <= viaB ? g.segA[to.seg] : g.segB[to.seg];
    const nodes: LonLat[] = [];
    while (n >= 0) { nodes.push(g.node(n)); n = this.pred[n]; }
    nodes.reverse();
    return [from.point, ...nodes, to.point];
  }

  private run(from: Cand, cutoff: number) {
    const g = this.g;
    for (const n of this.touched) { this.dist[n] = Infinity; this.pred[n] = -1; }
    this.touched = [];
    const heap = new MinHeap();
    const c = g.segCost[from.seg], len = g.segLen[from.seg];
    const seed = (n: number, d: number) => {
      if (d < this.dist[n]) { if (this.dist[n] === Infinity) this.touched.push(n); this.dist[n] = d; this.pred[n] = -1; heap.push(d, n); }
    };
    seed(g.segA[from.seg], from.t * len * c);
    seed(g.segB[from.seg], (1 - from.t) * len * c);
    while (heap.size) {
      const [d, u] = heap.pop();
      if (d > this.dist[u] || d > cutoff) continue;
      for (let e = g.adjStart[u]; e < g.adjStart[u + 1]; e++) {
        const v = g.adjNode[e], s = g.adjSeg[e];
        const nd = d + g.segLen[s] * g.segCost[s];
        if (nd < this.dist[v] && nd <= cutoff) {
          if (this.dist[v] === Infinity) this.touched.push(v);
          this.dist[v] = nd; this.pred[v] = u; heap.push(nd, v);
        }
      }
    }
  }
}

/** How far along the track a transition may wander relative to the straight-line gap. */
const transitionCutoff = (gc: number) => Math.max(2.5 * gc, gc + 400);

export function mapMatch(g: RailGraph, shape: LonLat[], opts: MatchOptions = DEFAULT_MATCH, router = new Router(g)): MatchResult {
  const pts = densify(shape, opts.sampleStep);
  const cands: Cand[][] = pts.map((p) => {
    let c = g.nearSegments(p, opts.radius, opts.maxCandidates);
    if (!c.length) c = g.nearSegments(p, opts.wideRadius, opts.maxCandidates);
    return c;
  });

  // Viterbi over points that have candidates. A chain breaks when no transition is feasible.
  const emission = (d: number) => -0.5 * (d / opts.sigma) ** 2;
  type Step = { i: number; score: number[]; back: number[] };
  const chains: Step[][] = [];
  let chain: Step[] = [];
  for (let i = 0; i < pts.length; i++) {
    const cs = cands[i];
    if (!cs.length) continue;
    const prev = chain[chain.length - 1];
    if (!prev) { chain.push({ i, score: cs.map((c) => emission(c.dist)), back: cs.map(() => -1) }); continue; }
    const pcs = cands[prev.i];
    const gc = haversine(pts[prev.i], pts[i]);
    const cutoff = transitionCutoff(gc);
    const score = cs.map(() => -Infinity), back = cs.map(() => -1);
    pcs.forEach((pc, a) => {
      if (prev.score[a] === -Infinity) return;
      const costs = router.costs(pc, cs, cutoff);
      costs.forEach((route, b) => {
        if (!Number.isFinite(route)) return;
        const s = prev.score[a] - Math.abs(route - gc) / opts.beta + emission(cs[b].dist);
        if (s > score[b]) { score[b] = s; back[b] = a; }
      });
    });
    if (score.every((s) => s === -Infinity)) {
      chains.push(chain);
      chain = [{ i, score: cs.map((c) => emission(c.dist)), back: cs.map(() => -1) }];
    } else chain.push({ i, score, back });
  }
  if (chain.length) chains.push(chain);

  const coords: LonLat[] = [];
  let matchedPts = 0, offsetSum = 0, breaks = 0, lastIdx = -1;
  const push = (p: LonLat) => {
    const last = coords[coords.length - 1];
    if (!last || last[0] !== p[0] || last[1] !== p[1]) coords.push(p);
  };
  for (const ch of chains) {
    if (ch.length < 2) continue; // a lone point is noise; leave it to the raw-shape fill
    // backtrack
    const lastStep = ch[ch.length - 1];
    let best = lastStep.score.indexOf(Math.max(...lastStep.score));
    const chosen: Cand[] = new Array(ch.length);
    for (let k = ch.length - 1; k >= 0; k--) { chosen[k] = cands[ch[k].i][best]; best = ch[k].back[best]; }
    // raw shape between the previous chain and this one
    if (lastIdx >= 0) { breaks++; for (let i = lastIdx + 1; i < ch[0].i; i++) push(pts[i]); }
    else for (let i = 0; i < ch[0].i; i++) push(pts[i]);
    push(chosen[0].point);
    for (let k = 1; k < ch.length; k++) {
      const gc = haversine(pts[ch[k - 1].i], pts[ch[k].i]);
      const path = router.path(chosen[k - 1], chosen[k], transitionCutoff(gc));
      if (path) for (const p of path) push(p); else push(chosen[k].point);
    }
    for (let k = 0; k < ch.length; k++) { if (!opts.inScope || opts.inScope(pts[ch[k].i])) matchedPts++; offsetSum += chosen[k].dist; }
    lastIdx = ch[ch.length - 1].i;
  }
  if (lastIdx < 0) return { coords: shape.slice(), matchedFraction: 0, meanOffset: Infinity, breaks: 0 };
  for (let i = lastIdx + 1; i < pts.length; i++) push(pts[i]);
  const scoped = opts.inScope ? pts.filter(opts.inScope).length : pts.length;
  return { coords, matchedFraction: scoped ? matchedPts / scoped : NaN, meanOffset: offsetSum / Math.max(1, matchedPts), breaks };
}
