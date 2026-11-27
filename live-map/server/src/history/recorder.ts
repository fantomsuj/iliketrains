// Records every live run into the history store as it happens, and answers history queries,
// filling past Amtrak days from the archive on demand.
import type { TrainState } from '../model.ts';
import type { GtfsFeed } from '../gtfs.ts';
import { serviceDay } from '../gtfs.ts';
import { type HistoryStore, type RunRow, onTimeThresholdSec } from './store.ts';
import { type ArchiveClient, toRun } from './archive.ts';

export const HISTORY_DAYS = 14;
const iso = (yyyymmdd: string) => `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`;

export interface HistoryDay {
  date: string; status: RunRow['status'] | 'unknown'; delayMin: number | null; measuredAt: string | null;
  scored: boolean; flag: string | null; source: RunRow['source'] | null; sourceUrl: string | null; consist: string | null;
}
export interface HistorySummary {
  operator: string; trainNumber: string; days: HistoryDay[]; thresholdMin: number;
  scoredRuns: number; onTimeRuns: number; onTimeRate: number | null; avgDelayMin: number | null; worstDelayMin: number | null;
  backfilling: boolean; note: string | null;
}

export class HistoryRecorder {
  private store: HistoryStore; private archive: ArchiveClient | null; private amtrakGtfs: GtfsFeed;
  private written = new Map<string, string>();
  private backfilling = new Set<string>();

  constructor(store: HistoryStore, archive: ArchiveClient | null, amtrakGtfs: GtfsFeed) {
    this.store = store; this.archive = archive; this.amtrakGtfs = amtrakGtfs;
  }

  /** Latest stop the train has actually passed, and its delay there. */
  static measure(t: TrainState): { station: string | null; delaySec: number | null } {
    const passed = t.stops.filter((s) => s.status === 'departed');
    for (let i = passed.length - 1; i >= 0; i--) {
      const s = passed[i];
      const sch = s.schArr ?? s.schDep, act = s.estArr ?? s.estDep;
      if (sch !== null && act !== null) return { station: s.name, delaySec: Math.round((act - sch) / 1000) };
    }
    return { station: null, delaySec: null };
  }

  record(t: TrainState, consist: string | null) {
    if (t.source !== 'live' || !t.serviceDate || t.status === 'scheduled') return;
    const m = HistoryRecorder.measure(t);
    const status = t.status === 'cancelled' ? 'cancelled' : t.status === 'completed' ? 'completed' : 'running';
    const key = `${t.operator}:${t.trainNumber}:${t.serviceDate}`;
    const fingerprint = `${m.station}|${m.delaySec}|${status}|${consist}`;
    if (this.written.get(key) === fingerprint) return;
    this.written.set(key, fingerprint);
    const { plan: _p, ...raw } = t;
    this.store.upsert({
      operator: t.operator, train_number: t.trainNumber, service_date: iso(t.serviceDate), source: 'live',
      route_name: t.routeName, origin: t.origin, destination: t.destination,
      measured_station: m.station, delay_sec: m.delaySec, scored: m.delaySec === null || status === 'cancelled' ? 0 : 1,
      flag: status === 'cancelled' ? 'cancelled' : m.delaySec === null ? 'no stop passed yet' : null, status,
      consist, source_url: null, raw: JSON.stringify(raw), updated_at: Date.now(),
    });
  }

  /** The train left the feed: its run is over (unless it never got going). */
  finish(t: TrainState) {
    if (!t.serviceDate || t.source !== 'live') return;
    if (t.status !== 'cancelled' && HistoryRecorder.measure(t).station) this.store.setStatus(t.operator, t.trainNumber, iso(t.serviceDate), 'completed');
  }

  summary(operator: string, trainNumber: string, now: number): HistorySummary {
    const dates: string[] = [];
    for (let i = 0; i < HISTORY_DAYS; i++) dates.push(iso(serviceDay(now, -i).date));
    const rows = this.store.runs(operator, trainNumber, dates[dates.length - 1]);
    const byDate = new Map<string, RunRow>();
    for (const r of rows) { const have = byDate.get(r.service_date); if (!have || (r.source === 'live' && r.delay_sec !== null)) byDate.set(r.service_date, r); }
    if (operator === 'amtrak' && this.archive) this.backfill(trainNumber, dates.slice(1).filter((d) => !byDate.has(d)));
    const days: HistoryDay[] = dates.map((date) => {
      const r = byDate.get(date);
      if (!r) return { date, status: 'unknown', delayMin: null, measuredAt: null, scored: false, flag: null, source: null, sourceUrl: null, consist: null };
      return { date, status: r.status, delayMin: r.delay_sec === null ? null : Math.round(r.delay_sec / 60), measuredAt: r.measured_station,
        scored: !!r.scored && r.status !== 'running', flag: r.flag, source: r.source, sourceUrl: r.source_url, consist: r.consist };
    });
    const thr = onTimeThresholdSec(operator);
    const scored = days.filter((d) => d.scored && d.delayMin !== null);
    const delays = scored.map((d) => d.delayMin!);
    const onTime = scored.filter((d) => d.delayMin! * 60 <= thr).length;
    return {
      operator, trainNumber, days, thresholdMin: Math.round(thr / 60),
      scoredRuns: scored.length, onTimeRuns: onTime, onTimeRate: scored.length ? onTime / scored.length : null,
      avgDelayMin: delays.length ? Math.round((delays.reduce((a, b) => a + b, 0) / delays.length) * 10) / 10 : null,
      worstDelayMin: delays.length ? Math.max(...delays) : null,
      backfilling: this.backfilling.has(trainNumber),
      note: operator === 'amtrak' ? null : 'Recorded by Trains from the live feed; history builds up day by day.',
    };
  }

  raw(operator: string, trainNumber: string, date: string): RunRow | undefined {
    return this.store.get(operator, trainNumber, date, 'live') ?? this.store.get(operator, trainNumber, date, 'archive');
  }

  private backfill(trainNumber: string, dates: string[]) {
    if (!dates.length || this.backfilling.has(trainNumber) || !this.archive) return;
    this.backfilling.add(trainNumber);
    const archive = this.archive;
    void (async () => {
      try {
        for (const date of dates) {
          const d = await archive.fetchDay(trainNumber, date);
          if (d) this.store.upsert(toRun(trainNumber, date, d, this.amtrakGtfs));
          else this.store.upsert({ operator: 'amtrak', train_number: trainNumber, service_date: date, source: 'archive', route_name: '', origin: '', destination: '',
            measured_station: null, delay_sec: null, scored: 0, flag: 'did not run (no record)', status: 'no_record', consist: null,
            source_url: `https://asm.transitdocs.com/train/${date.replaceAll('-', '/')}/A/${trainNumber}`, raw: '{}', updated_at: Date.now() });
        }
      } catch (e) { console.error(`[history] archive backfill for ${trainNumber} stopped:`, (e as Error).message); }
      finally { this.backfilling.delete(trainNumber); }
    })();
  }
}

/** "M7 x 12 cars, lead car 7524" for the per-day equipment line. */
export function consistLabel(c: { name: string; carsRunning: number | null; cars: { number: number | null; locomotive: boolean }[] } | null): string | null {
  if (!c || !c.cars.length) return null;
  const lead = c.cars.find((x) => x.locomotive)?.number ?? c.cars[0].number;
  return `${c.name}, ${c.carsRunning ?? c.cars.length} cars${lead ? `, lead ${c.cars[0].locomotive ? 'loco' : 'car'} ${lead}` : ''}`;
}
