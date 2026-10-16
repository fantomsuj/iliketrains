import { test } from 'node:test';
import assert from 'node:assert/strict';
import { type LonLat, Polyline, haversine } from '../src/geo/geo.ts';
import { RailGraph, type RailWay, parseOplWay } from '../src/build/railgraph.ts';
import { mapMatch } from '../src/build/mapmatch.ts';

// Metres -> degrees near 41N (local flat frame used to lay out test track).
const LAT0 = 41, LON0 = -73;
const M_LAT = 1 / 111195, M_LON = 1 / (111195 * Math.cos(LAT0 * Math.PI / 180));
const at = (x: number, y: number): LonLat => [LON0 + x * M_LON, LAT0 + y * M_LAT];

let nextNode = 1;
function way(id: number, pts: [number, number][], tags: Record<string, string> = { railway: 'rail', usage: 'main' }, ids?: number[]): RailWay {
  const nodes = ids ?? pts.map(() => nextNode++);
  return { id, tags, nodes, coords: pts.map(([x, y]) => at(x, y)) };
}
function line(x0: number, x1: number, y: number, step = 100): [number, number][] {
  const out: [number, number][] = [];
  for (let x = x0; x <= x1; x += step) out.push([x, y]);
  return out;
}
/** Max distance from any point of `coords` to the reference line. */
function maxDeviation(coords: LonLat[], ref: LonLat[]): number {
  const r = new Polyline(ref);
  return Math.max(...coords.map((c) => r.project(c).offset));
}
const jitter = (i: number) => Math.sin(i * 12.9898) * 8; // deterministic +-8 m noise

test('noisy shape along one of two parallel tracks stays on the nearer track', () => {
  // Two tracks 30 m apart (typical multi-track main line). Shape runs 8 m off the north track.
  const north = way(1, line(0, 5000, 30));
  const south = way(2, line(0, 5000, 0));
  const g = new RailGraph([north, south]);
  const shape = line(0, 5000, 30, 250).map(([x, y], i): LonLat => at(x, y - 8 + jitter(i)));
  const m = mapMatch(g, shape);
  assert.ok(m.matchedFraction > 0.95, `matched ${m.matchedFraction}`);
  assert.ok(maxDeviation(m.coords, north.coords) < 1, 'every output point lies on the north track');
  assert.equal(m.breaks, 0);
});

test('follows a diverging branch at a junction instead of the straight main line', () => {
  // Main line along y=0; a branch leaves at x=2000 heading north-east.
  const mainIds = line(0, 6000, 0).map(() => nextNode++);
  const main = way(10, line(0, 6000, 0), undefined, mainIds);
  const junction = mainIds[20]; // node at x=2000
  const branchPts: [number, number][] = [[2000, 0]];
  for (let k = 1; k <= 30; k++) branchPts.push([2000 + k * 100, k * 70]);
  const branch = way(11, branchPts, { railway: 'rail', usage: 'branch' }, [junction, ...branchPts.slice(1).map(() => nextNode++)]);
  const g = new RailGraph([main, branch]);
  // Shape: main line to the junction, then the branch.
  const shape: LonLat[] = [...line(0, 2000, 0, 200).map(([x, y]) => at(x, y + 5)), ...branchPts.slice(1).filter((_, i) => i % 2 === 0).map(([x, y]) => at(x + 5, y))];
  const m = mapMatch(g, shape);
  const end = m.coords[m.coords.length - 1];
  assert.ok(haversine(end, at(4900, 2030)) < 30, 'ends on the branch where the shape ends');
  // never strays onto the main line beyond the junction
  const strayed = m.coords.some((c) => c[0] > at(2100, 0)[0] && Math.abs(c[1] - LAT0) < 10 * M_LAT);
  assert.equal(strayed, false);
  // track distance close to true distance (2000 m main + 30 * sqrt(100^2+70^2) branch)
  const truth = 2000 + 29 * Math.hypot(100, 70);
  assert.ok(Math.abs(new Polyline(m.coords).length - truth) < 60, `length ${new Polyline(m.coords).length} vs ${truth}`);
});

test('prefers the running line over a parallel yard track', () => {
  const runIds = line(0, 3000, 0).map(() => nextNode++);
  const run = way(20, line(0, 3000, 0), undefined, runIds);
  // Yard track 12 m away and the shape is drawn between them, slightly closer to the yard.
  const yard = way(21, line(0, 3000, 12), { railway: 'rail', service: 'yard' });
  const g = new RailGraph([run, yard]);
  const shape = line(0, 3000, 0, 300).map(([x, y]) => at(x, y + 7));
  const m = mapMatch(g, shape);
  // Emission slightly favours the yard; transitions on the yard cost 4x, so the run wins overall.
  assert.ok(maxDeviation(m.coords, run.coords) < 1, 'output lies on the running line');
});

test('bridges a gap in the track data with the raw shape and reports the break', () => {
  const a = way(30, line(0, 2000, 0));
  const b = way(31, line(4000, 6000, 0)); // 2 km missing from the map
  const g = new RailGraph([a, b]);
  const shape = line(0, 6000, 0, 200).map(([x, y]) => at(x, y + 3));
  const m = mapMatch(g, shape);
  assert.equal(m.breaks, 1);
  assert.ok(m.matchedFraction > 0.6 && m.matchedFraction < 0.75, `matched ${m.matchedFraction}`);
  const len = new Polyline(m.coords).length;
  assert.ok(Math.abs(len - 6000) < 50, `continuous line, length ${len}`);
});

test('shape entirely outside the network passes through unchanged', () => {
  const g = new RailGraph([way(40, line(0, 1000, 0))]);
  const shape: LonLat[] = [at(0, 50000), at(1000, 50000)];
  const m = mapMatch(g, shape);
  assert.equal(m.matchedFraction, 0);
  assert.deepEqual(m.coords, shape);
});

test('parses osmium OPL ways with locations and escaped tags', () => {
  const w = parseOplWay('w42 v3 dV c1 t2020-01-01T00:00:00Z i1 ufoo Trailway=rail,name=Hudson%20%Line,usage=main Nn1x-73.9y40.7,n2x-73.8y40.8,n3');
  assert.ok(w);
  assert.equal(w.id, 42);
  assert.equal(w.tags.name, 'Hudson Line');
  assert.deepEqual(w.nodes, [1, 2]);
  assert.deepEqual(w.coords, [[-73.9, 40.7], [-73.8, 40.8]]);
});

test('routes between sparse stations along a curving track, not the straight line', async () => {
  const { STOPS_MATCH } = await import('../src/build/build-routes.ts');
  // A track that bows 3 km north between two stations 10 km apart.
  const pts: [number, number][] = [];
  for (let x = 0; x <= 10000; x += 100) pts.push([x, 3000 * Math.sin((Math.PI * x) / 10000)]);
  const g = new RailGraph([way(50, pts)]);
  const m = mapMatch(g, [at(0, 40), at(10000, -30)], STOPS_MATCH);
  const len = new Polyline(m.coords).length;
  const truth = new Polyline(pts.map(([x, y]) => at(x, y))).length;
  assert.ok(Math.abs(len - truth) < 150, `length ${Math.round(len)} vs track ${Math.round(truth)}`);
  assert.ok(maxDeviation(m.coords, pts.map(([x, y]) => at(x, y))) < 60, 'follows the curve');
});
