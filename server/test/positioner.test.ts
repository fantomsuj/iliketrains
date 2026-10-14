import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Positioner } from '../src/live/positioner.ts';
import { RouteIndex, type RoutesFile } from '../src/routes.ts';
import { encodePolyline, type LonLat } from '../src/geo/geo.ts';
import type { RawTrain } from '../src/model.ts';
import { distanceAt } from '../src/motion.ts';

// A straight 20 km east-west line at 41N with stations A (0 km), B (10 km), C (20 km).
const M_LON = 1 / (111195 * Math.cos((41 * Math.PI) / 180));
const at = (x: number): LonLat => [-73 + x * M_LON, 41];
const coords: LonLat[] = []; for (let x = 0; x <= 20000; x += 250) coords.push(at(x));
const file: RoutesFile = { generatedAt: '', license: '', railSource: '', overview: [],
  shapes: { 't:s1': { feed: 't', shapeId: 's1', polyline: encodePolyline(coords), lengthM: 20000, matchedFraction: 1, meanOffset: 0, breaks: 0 } },
  patterns: { lirr: { 's1|A,B,C': { shape: 't:s1', stops: ['A', 'B', 'C'], dist: [0, 10000, 20000], maxStopOffset: 0 } } } };
const stations = { hubOf: (_o: string, id: string) => id, name: (_o: string, id: string) => id };
const T0 = 1_800_000_000_000;

function raw(over: Partial<RawTrain> = {}): RawTrain {
  return { tripId: 'x', operator: 'lirr', route: 'r', routeName: 'Test', trainNumber: '1', stops: [
    { stationId: 'A', schDep: T0, estDep: T0, departed: true },
    { stationId: 'B', schArr: T0 + 600_000, schDep: T0 + 630_000, estArr: T0 + 600_000, estDep: T0 + 630_000, departed: false },
    { stationId: 'C', schArr: T0 + 1_200_000, estArr: T0 + 1_200_000, departed: false } ],
    delaySec: 0, source: 'live', updatedAt: T0, shape: { shapeId: 's1', stations: ['A', 'B', 'C'] }, ...over };
}
const gps = (x: number, t: number) => { const [lon, lat] = at(x); return { lon, lat, at: t, speedMps: 17 }; };

test('timetable-only position interpolates between stops', () => {
  const p = new Positioner(new RouteIndex(file), new Map(), stations);
  const s = p.position(raw(), T0 + 300_000);
  assert.equal(s.fix, 'predicted');
  assert.ok(Math.abs(s.distM - 5000) < 50, `at ${s.distM}`);
  assert.ok(Math.abs(s.progress - 0.25) < 0.01);
  assert.equal(s.next?.stationId, 'B');
});

test('GPS fix is snapped onto the route and used as the motion anchor', () => {
  const p = new Positioner(new RouteIndex(file), new Map(), stations);
  const s = p.position(raw({ position: gps(4000, T0 + 290_000) }), T0 + 300_000);
  assert.equal(s.fix, 'gps');
  assert.equal(s.plan!.d0, 4000);
  assert.equal(s.plan!.t0, T0 + 290_000);
  // dead reckoning from the fix toward B's predicted arrival (6 km in 310 s)
  assert.ok(Math.abs(distanceAt(s.plan!, T0 + 600_000) - 10000) < 1);
});

test('an implausible GPS jump is held until a second fix confirms it', () => {
  const p = new Positioner(new RouteIndex(file), new Map(), stations);
  const a = p.position(raw({ position: gps(4000, T0 + 290_000) }), T0 + 300_000);
  // 20 s later the feed claims the train is 8 km further on (400 m/s): ignored
  const b = p.position(raw({ position: gps(12000, T0 + 310_000) }), T0 + 320_000, a);
  assert.ok(b.plan!.d0 < 5000, `held at ${b.plan!.d0}`);
  // a consistent second report 20 s after that is accepted
  const c = p.position(raw({ position: gps(12300, T0 + 330_000) }), T0 + 340_000, b);
  assert.equal(c.plan!.d0, 12300);
});

test('small backward GPS noise never moves the train backward', () => {
  const p = new Positioner(new RouteIndex(file), new Map(), stations);
  const a = p.position(raw({ position: gps(4000, T0 + 290_000) }), T0 + 300_000);
  const b = p.position(raw({ position: gps(3900, T0 + 310_000) }), T0 + 320_000, a);
  assert.ok(b.plan!.d0 >= distanceAt(a.plan!, T0 + 310_000) - 1, 'not behind where it was shown');
});

test('a report far from the route is ignored in favour of stop times', () => {
  const p = new Positioner(new RouteIndex(file), new Map(), stations);
  const far = { lon: at(4000)[0], lat: 41.05, at: T0 + 290_000 }; // 5.5 km north of the line
  const s = p.position(raw({ position: far }), T0 + 300_000);
  assert.equal(s.fix, 'predicted');
});

test('a missing GPS report keeps the train gliding on its last fix', () => {
  const p = new Positioner(new RouteIndex(file), new Map(), stations);
  const a = p.position(raw({ position: gps(2000, T0 + 290_000) }), T0 + 300_000); // behind the timetable (5 km)
  const b = p.position(raw(), T0 + 320_000, a);
  assert.equal(b.fix, 'gps');
  assert.ok(Math.abs(b.plan!.d0 - distanceAt(a.plan!, T0 + 320_000)) < 1, 'continues from the previous plan, not the timetable');
});
