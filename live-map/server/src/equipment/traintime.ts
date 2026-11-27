// LIRR and Metro-North equipment from the backend of the MTA's own TrainTime app
// (backend-unified.mylirr.org, the same calls traintime.mta.info makes). Undocumented: we
// poll it from the server only, every POLL_MS, and cache, so phones never call it directly.
import type { Fetcher } from '../live/fetcher.ts';
import { CAR_MODELS, fleetName } from './models.ts';

const BASE = 'https://backend-unified.mylirr.org';
const HEADERS = { 'Accept-Version': '3.0' };
export const POLL_MS = 20_000;

export interface Car {
  position: number; number: number | null; type: string; model: string; locomotive: boolean;
  /** EMPTY / MANY_SEATS / FEW_SEATS / FULL as reported; NO_DATA when the car has no sensor */
  loading: string; passengers: number | null; restroom: boolean; bikes: number | null;
}
export interface Consist {
  fleet: string | null; name: string; carsRunning: number | null; carsScheduled: number | null;
  occupancy: string; cars: Car[]; observedAt: number; sourceUrl: string; live: true;
}
export interface Equipment { live: false; summary: string; detail: string; source: string }

interface TTStop { code: string; sign_track?: string; t2s_track?: string; track_change?: boolean }
interface TTTrain {
  train_id: string; railroad: 'LIRR' | 'MNR'; run_date: string; train_num: string;
  consist?: { fleet?: string; actual_len?: number; sched_len?: number; occupancy?: string;
    cars?: { type: string; number?: number; loading?: string; passengers?: number; restroom?: boolean; bikes?: number; locomotive?: boolean }[] };
  details?: { stops?: TTStop[] };
  location?: { timestamp?: number };
}

export class TrainTimeEquipment {
  private fetcher: Fetcher;
  private byTrain = new Map<string, TTTrain[]>(); // "lirr:1902" -> runs (by run_date)
  private stationGtfs = new Map<string, string>(); // "LIRR:PWS" -> gtfs stop id
  lastOk = 0; lastError: string | null = null;

  constructor(fetcher: Fetcher) { this.fetcher = fetcher; }

  async poll(): Promise<void> {
    try {
      if (!this.stationGtfs.size) {
        const inf = await this.fetcher.get('traintime-stations', `${BASE}/infrastructure?fields=stations`, { headers: HEADERS, maxAgeMs: 24 * 3600_000 });
        if (inf) for (const s of JSON.parse(inf.toString('utf8')).stations ?? []) if (s.gtfs_stop_id != null) this.stationGtfs.set(`${s.railroad}:${s.code}`, String(s.gtfs_stop_id));
      }
      const body = await this.fetcher.get('traintime', `${BASE}/locations?geometry=NONE`, { headers: HEADERS });
      if (!body) return;
      const list = JSON.parse(body.toString('utf8')) as TTTrain[];
      const next = new Map<string, TTTrain[]>();
      for (const t of list) {
        const k = `${t.railroad === 'LIRR' ? 'lirr' : 'mnr'}:${t.train_num}`;
        next.set(k, [...(next.get(k) ?? []), t]);
      }
      this.byTrain = next; this.lastOk = Date.now(); this.lastError = null;
    } catch (e) { this.lastError = String((e as Error).message ?? e); }
  }

  private find(operator: string, trainNumber: string, serviceDate?: string): TTTrain | undefined {
    const runs = this.byTrain.get(`${operator}:${trainNumber}`);
    if (!runs?.length) return undefined;
    const iso = serviceDate && /^\d{8}$/.test(serviceDate) ? `${serviceDate.slice(0, 4)}-${serviceDate.slice(4, 6)}-${serviceDate.slice(6)}` : serviceDate;
    return runs.find((r) => r.run_date === iso) ?? [...runs].sort((a, b) => (a.run_date < b.run_date ? 1 : -1))[0];
  }

  consist(operator: string, trainNumber: string, serviceDate?: string): Consist | null {
    const t = this.find(operator, trainNumber, serviceDate);
    const c = t?.consist;
    if (!t || !c) return null;
    const cars = (c.cars ?? []).map((x, i): Car => ({
      position: i + 1, number: x.number ?? null, type: x.type,
      model: CAR_MODELS[x.type] ? `${CAR_MODELS[x.type].maker} ${CAR_MODELS[x.type].name}` : x.type,
      locomotive: !!x.locomotive, loading: x.loading ?? 'NO_DATA', passengers: x.passengers ?? null,
      restroom: !!x.restroom, bikes: x.bikes ?? null,
    }));
    return { fleet: c.fleet ?? null, name: fleetName(c.fleet, cars[0]?.type), carsRunning: c.actual_len ?? (cars.length || null),
      carsScheduled: c.sched_len ?? null, occupancy: c.occupancy ?? 'NO_DATA', cars,
      observedAt: (t.location?.timestamp ?? 0) * 1000 || this.lastOk, sourceUrl: `${BASE}/locations/${t.train_id}?geometry=NONE`, live: true };
  }

  /** Posted track per timetable station id for this run. */
  tracks(operator: string, trainNumber: string, serviceDate?: string): Map<string, { track: string; changed: boolean }> {
    const out = new Map<string, { track: string; changed: boolean }>();
    const t = this.find(operator, trainNumber, serviceDate);
    const rr = operator === 'lirr' ? 'LIRR' : 'MNR';
    for (const s of t?.details?.stops ?? []) {
      const gtfs = this.stationGtfs.get(`${rr}:${s.code}`);
      const track = s.sign_track || s.t2s_track;
      if (gtfs && track) out.set(gtfs, { track, changed: !!s.track_change });
    }
    return out;
  }

  /** Raw TrainTime record for the "view raw" link. */
  raw(operator: string, trainNumber: string, serviceDate?: string): unknown { return this.find(operator, trainNumber, serviceDate) ?? null; }
}
