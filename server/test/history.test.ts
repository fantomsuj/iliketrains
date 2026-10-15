import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { GtfsFeed } from '../src/gtfs.ts';
import { matchesTimetable, toRun } from '../src/history/archive.ts';
import { HistoryStore } from '../src/history/store.ts';
import { HistoryRecorder, consistLabel } from '../src/history/recorder.ts';
import type { TrainState } from '../src/model.ts';

const fx = (p: string) => new URL(`./fixtures/${p}`, import.meta.url).pathname;
// Amtrak's real timetable for train 2150: a weekday schedule from Nov 16 and a temporary later
// schedule (Oct 14 - Nov 13). Archive records are real responses for Oct 8 and Oct 14, 2026.
const gtfs = new GtfsFeed('amtrak', fx('gtfs-2150'));
const asm = (d: string) => JSON.parse(fs.readFileSync(fx(`asm/2150_${d}.json`), 'utf8'));

test('archive day consistent with the timetable and its own times is scored', () => {
  const r = toRun('2150', '2026-10-08', asm('2026-10-08'), gtfs);
  assert.equal(r.scored, 1, String(r.flag));
  // last stop with an actual, like-for-like arrival (later stops are estimated or mismatched)
  assert.equal(r.measured_station, 'STM');
  assert.equal(r.delay_sec, -240);
  assert.match(r.source_url!, /asm\.transitdocs\.com\/train\/2026\/10\/08\/A\/2150$/);
});

test('archive day that gains an impossible amount of time en route is not scored', () => {
  // Oct 14: left Washington on time, "13 min early" at Stamford on a schedule with no extra padding
  const r = toRun('2150', '2026-10-14', asm('2026-10-14'), gtfs);
  assert.equal(matchesTimetable(gtfs, '2150', '2026-10-14', asm('2026-10-14').stops), true);
  assert.equal(r.delay_sec, -780);
  assert.equal(r.scored, 0);
  assert.match(r.flag!, /add up/);
});

test('archive day whose schedule matches no published timetable for that date is not scored', () => {
  // The Oct 8 record (early schedule) Oct 8 record claimed for Oct 20 (inside the temporary-schedule window) does not match.
  const wrong = toRun('2150', '2026-10-20', asm('2026-10-08'), gtfs);
  assert.equal(wrong.scored, 0);
  assert.equal(wrong.flag, 'compared against a different timetable');
});

function train(over: Partial<TrainState> = {}): TrainState {
  return { id: 'lirr:x', operator: 'lirr', tripId: 'x', serviceDate: '20261015', trainNumber: '1902', route: '', routeName: 'Babylon', headsign: '',
    color: '#000', shape: null, distM: 0, lat: 0, lon: 0, bearing: 0, speedMps: 0, delaySec: 120, source: 'live', fix: 'gps', status: 'enroute',
    updatedAt: 0, plan: null, origin: 'Penn', destination: 'Babylon', progress: 0.5, next: null,
    stops: [
      { stationId: 'A', hubId: 'A', name: 'Penn', d: 0, schArr: null, schDep: 1_000_000, estArr: null, estDep: 1_060_000, status: 'departed' },
      { stationId: 'B', hubId: 'B', name: 'Jamaica', d: 1, schArr: 2_000_000, schDep: 2_000_000, estArr: 2_240_000, estDep: 2_260_000, status: 'departed' },
      { stationId: 'C', hubId: 'C', name: 'Babylon', d: 2, schArr: 3_000_000, schDep: null, estArr: 3_300_000, estDep: null, status: 'upcoming' },
    ], ...over } as TrainState;
}

test('live runs are recorded at the latest stop passed, finished on leaving the feed, and summarised', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'trains-history-'));
  const rec = new HistoryRecorder(new HistoryStore(dir), null, gtfs);
  const t = train();
  rec.record(t, 'Bombardier M7 electric, 12 cars, lead car 7524');
  rec.finish(t);
  const now = Date.parse('2026-10-15T16:00:00Z');
  const s = rec.summary('lirr', '1902', now);
  const today = s.days.find((d) => d.date === '2026-10-15')!;
  assert.equal(today.delayMin, 4);          // Jamaica: 2,240,000 vs 2,000,000 ms
  assert.equal(today.measuredAt, 'Jamaica');
  assert.equal(today.status, 'completed');
  assert.equal(today.consist, 'Bombardier M7 electric, 12 cars, lead car 7524');
  assert.equal(s.thresholdMin, 6);          // MTA counts within 5:59 as on time
  assert.equal(s.scoredRuns, 1);
  assert.equal(s.onTimeRuns, 1);
  assert.equal(s.days.length, 14);
  fs.rmSync(dir, { recursive: true });
});

test('a run still under way does not count toward on-time figures', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'trains-history-'));
  const rec = new HistoryRecorder(new HistoryStore(dir), null, gtfs);
  rec.record(train(), null);
  const s = rec.summary('lirr', '1902', Date.parse('2026-10-15T16:00:00Z'));
  assert.equal(s.days[0].status, 'running');
  assert.equal(s.scoredRuns, 0);
  fs.rmSync(dir, { recursive: true });
});

test('consist label names the fleet, car count and lead unit', () => {
  assert.equal(consistLabel({ name: 'Siemens Charger diesel', carsRunning: 7, cars: [{ number: 308, locomotive: true }, { number: 6456, locomotive: false }] }),
    'Siemens Charger diesel, 7 cars, lead loco 308');
  assert.equal(consistLabel(null), null);
});
