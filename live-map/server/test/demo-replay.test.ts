// End-to-end: replay the bundled demo recording through the real engine and check the output.
// Needs static GTFS (npm run fetch:gtfs); skipped when it is missing.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const haveGtfs = fs.existsSync(path.join(root, 'data/gtfs/amtrak/trips.txt'));

test('demo replay positions trains from every feed on their routes', { skip: !haveGtfs && 'static GTFS not downloaded' }, async () => {
  process.env.TRAINS_DEMO = '1';
  const { Engine } = await import('../src/live/engine.ts');
  const { RouteIndex } = await import('../src/routes.ts');
  const { config } = await import('../src/config.ts');
  const { inRegion } = await import('../src/region.ts');
  const routes = RouteIndex.load(config.routesFile);
  const engine = new Engine(routes);
  const adapters = (engine as unknown as { adapters: { id: string }[] }).adapters;
  for (const a of adapters) await engine.pollAdapter(a as never);
  const snap = engine.snapshot();
  const byOp = new Map<string, number>();
  for (const t of snap.trains) byOp.set(t.operator, (byOp.get(t.operator) ?? 0) + 1);
  for (const op of ['amtrak', 'lirr', 'mnr', 'njt']) assert.ok((byOp.get(op) ?? 0) > 20, `${op}: ${byOp.get(op)} trains`);
  // nearly every train has route geometry and a motion plan
  const withPlan = snap.trains.filter((t) => t.shape && t.plan).length;
  assert.ok(withPlan / snap.trains.length > 0.97, `${withPlan}/${snap.trains.length} have a plan`);
  // positions are real coordinates, and (Amtrak long-distance legs aside) inside the region
  const commuter = snap.trains.filter((t) => t.operator !== 'amtrak');
  assert.ok(commuter.every((t) => inRegion([t.lon, t.lat])), 'commuter trains are inside the region');
  // GPS-fixed trains sit on their route line at the report time
  const gps = snap.trains.filter((t) => t.fix === 'gps');
  assert.ok(gps.length > 50, `${gps.length} GPS-fixed trains`);
  // a station board for New York Penn lists trains from three operators
  const board = engine.board('amtrak:NYP')!;
  assert.deepEqual(new Set(board.rows.map((r) => r.operator)), new Set(['amtrak', 'njt', 'lirr']));
  // station stats for New York Penn: today's timetabled departures, split by line, adding up
  const st = engine.stationStats('amtrak:NYP')!;
  assert.ok(st.departures > 100, `${st.departures} departures`);
  assert.equal(st.lines.reduce((a, l) => a + l.count, 0), st.departures);
  assert.equal(st.perHour.reduce((a: number, n: number) => a + n, 0), st.departures);
  assert.deepEqual(new Set(st.lines.map((l) => l.operator)), new Set(['amtrak', 'njt', 'lirr']));
  assert.ok(st.destinations[0].count >= st.destinations[st.destinations.length - 1].count);
  assert.ok(['ok', 'minor', 'major', 'unknown'].includes(st.status.level));
  // search finds a train by its exact number
  const someNumber = snap.trains.find((t) => t.operator === 'lirr')!.trainNumber;
  assert.ok(engine.search(someNumber).trains.some((t) => t.trainNumber === someNumber));
});
