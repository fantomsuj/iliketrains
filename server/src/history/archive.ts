// Past Amtrak runs from the ASM archive (asm.transitdocs.com, backend asm-backend.transitdocs.com).
// No published API: fetched server-side only, one request every few seconds, cached forever.
import type { GtfsFeed } from '../gtfs.ts';
import type { RunRow } from './store.ts';

const BASE = 'https://asm-backend.transitdocs.com/train';
const SPACING_MS = 2500;
/**
 * How much time a train can plausibly make up between its origin and a stop: schedules carry
 * padding roughly in proportion to their length (a long-distance train often arrives an hour
 * early), so allow 10 min or 10% of the scheduled running time, whichever is more. A run that
 * "gains" more than that was compared against the wrong times.
 */
export function allowedGainS(origin: AsmStop | undefined, at: AsmStop | undefined): number {
  const from = origin?.sched_depart ?? origin?.sched_arrive, to = at?.sched_arrive ?? at?.sched_depart;
  return Math.max(600, from && to ? 0.1 * (to - from) : 0);
}

interface AsmStop {
  code: string; sched_arrive?: number; sched_depart?: number; canceled?: boolean;
  arrive?: { variance: number; type: 'ACTUAL' | 'ESTIMATED'; times_compared: string };
  depart?: { variance: number; type: 'ACTUAL' | 'ESTIMATED'; times_compared: string };
}
interface AsmTrain { name: string; origin?: { code?: string }; destination?: { code?: string }; stops: AsmStop[]; disruption?: boolean }

const hhmm = (epochS: number) => new Intl.DateTimeFormat('en-GB', { timeZone: 'America/New_York', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date(epochS * 1000));
const minutesOf = (s: string) => { const [h, m] = s.split(':').map(Number); return (h % 24) * 60 + m; };

/**
 * Does the archive's schedule for this day match Amtrak's own published timetable for that
 * date? If no timetable trip with this number runs then at the same times, the archive
 * compared the run against the wrong schedule and the delay would mislead.
 */
export function matchesTimetable(gtfs: GtfsFeed, trainNumber: string, date: string, stops: AsmStop[]): boolean | null {
  // Prefer the timetable in force on that exact date (temporary schedules matter); for dates the
  // current timetable no longer covers, fall back to trips that run on that weekday.
  const dow = new Date(`${date}T12:00:00Z`).getUTCDay();
  const numbered = [...gtfs.trips.values()].filter((t) => t.shortName === trainNumber);
  const onDate = numbered.filter((t) => gtfs.runsOn(t.serviceId, date.replaceAll('-', '')));
  const trips = onDate.length ? onDate : numbered.filter((t) => gtfs.runsOnWeekday(t.serviceId, dow));
  if (!trips.length) return null; // the timetable can't tell us
  const archive = new Map(stops.filter((s) => s.sched_arrive || s.sched_depart).map((s) => [s.code, minutesOf(hhmm((s.sched_depart ?? s.sched_arrive)!))]));
  return trips.some((t) => {
    let common = 0, close = 0;
    t.stopIds.forEach((sid, i) => {
      const a = archive.get(gtfs.stationOf(sid));
      if (a === undefined) return;
      common++;
      const g = Math.floor(t.dep[i] / 60) % 1440;
      const diff = Math.min(Math.abs(a - g), 1440 - Math.abs(a - g));
      if (diff <= 5) close++; // the two sources disagree by a few minutes at the origin; a wrong schedule is off by hours
    });
    return common >= 2 && close / common >= 0.8;
  });
}

/** Turn one archive record into a history row (the latest stop with an actual, like-for-like time). */
export function toRun(trainNumber: string, date: string, d: AsmTrain, gtfs: GtfsFeed): RunRow {
  const usable = d.stops.filter((s) => s.arrive?.type === 'ACTUAL' && s.arrive.times_compared !== 'MISMATCH_ARRIVAL');
  const last = usable[usable.length - 1];
  const delay = last ? last.arrive!.variance : null;
  const tt = matchesTimetable(gtfs, trainNumber, date, d.stops);
  const originDep = d.stops[0]?.depart?.type === 'ACTUAL' ? d.stops[0].depart.variance : null;
  let flag: string | null = null;
  if (d.stops.length && d.stops.every((s) => s.canceled)) flag = 'cancelled';
  else if (tt === false) flag = 'compared against a different timetable';
  else if (tt === null && delay !== null && delay < -600) flag = 'more than 10 min early: likely a different timetable';
  else if (delay !== null && originDep !== null && delay < originDep - allowedGainS(d.stops[0], last)) flag = "times don't add up (gained too much time en route)";
  else if (delay === null) flag = 'no actual times recorded';
  const final = d.stops[d.stops.length - 1];
  return {
    operator: 'amtrak', train_number: trainNumber, service_date: date, source: 'archive', route_name: d.name ?? '',
    origin: d.stops[0]?.code ?? '', destination: final?.code ?? '', measured_station: last?.code ?? null, delay_sec: delay,
    scored: flag ? 0 : 1, flag, status: flag === 'cancelled' ? 'cancelled' : 'completed', consist: null,
    source_url: `https://asm.transitdocs.com/train/${date.replaceAll('-', '/')}/A/${trainNumber}`,
    raw: JSON.stringify(d), updated_at: Date.now(),
  };
}

export class ArchiveClient {
  private userAgent: string;
  private queue: Promise<void> = Promise.resolve();
  constructor(userAgent: string) { this.userAgent = userAgent; }

  /** Fetch one train-day; null when the archive has no record. Calls are serialised and spaced. */
  fetchDay(trainNumber: string, date: string): Promise<AsmTrain | null> {
    const run = this.queue.then(async () => {
      const res = await fetch(`${BASE}/${date.replaceAll('-', '/')}/A/${encodeURIComponent(trainNumber)}`,
        { headers: { 'User-Agent': this.userAgent }, signal: AbortSignal.timeout(15_000) });
      await new Promise((r) => setTimeout(r, SPACING_MS));
      if (res.status === 404) return null;
      if (!res.ok) throw new Error(`archive HTTP ${res.status}`);
      const d = (await res.json()) as AsmTrain;
      return d.stops ? d : null;
    });
    this.queue = run.then(() => undefined, () => undefined);
    return run;
  }
}
