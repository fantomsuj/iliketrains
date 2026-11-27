// Run history: one row per train per service day per source (our own live recording, or the
// public Amtrak archive). SQLite via node:sqlite, in TRAINS_DATA_DIR.
import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export type RunSource = 'live' | 'archive';
export type RunStatus = 'running' | 'completed' | 'cancelled' | 'no_record';

export interface RunRow {
  operator: string; train_number: string; service_date: string; source: RunSource;
  route_name: string; origin: string; destination: string;
  measured_station: string | null; delay_sec: number | null;
  /** 1 when the run counts toward on-time figures; 0 with a flag explaining why not */
  scored: number; flag: string | null; status: RunStatus;
  consist: string | null; source_url: string | null; raw: string; updated_at: number;
}

export class HistoryStore {
  private db: DatabaseSync;
  constructor(dir: string) {
    fs.mkdirSync(dir, { recursive: true });
    this.db = new DatabaseSync(path.join(dir, 'history.sqlite'));
    this.db.exec(`create table if not exists runs (
      operator text not null, train_number text not null, service_date text not null, source text not null,
      route_name text, origin text, destination text, measured_station text, delay_sec integer,
      scored integer not null default 0, flag text, status text not null, consist text, source_url text,
      raw text not null, updated_at integer not null,
      primary key (operator, train_number, service_date, source))`);
  }

  upsert(r: RunRow) {
    this.db.prepare(`insert into runs values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      on conflict(operator, train_number, service_date, source) do update set
        route_name=excluded.route_name, origin=excluded.origin, destination=excluded.destination,
        measured_station=excluded.measured_station, delay_sec=excluded.delay_sec, scored=excluded.scored,
        flag=excluded.flag, status=excluded.status, consist=coalesce(excluded.consist, runs.consist),
        source_url=excluded.source_url, raw=excluded.raw, updated_at=excluded.updated_at`)
      .run(r.operator, r.train_number, r.service_date, r.source, r.route_name, r.origin, r.destination,
        r.measured_station, r.delay_sec, r.scored, r.flag, r.status, r.consist, r.source_url, r.raw, r.updated_at);
  }

  setStatus(operator: string, trainNumber: string, serviceDate: string, status: RunStatus) {
    this.db.prepare(`update runs set status=? where operator=? and train_number=? and service_date=? and source='live'`).run(status, operator, trainNumber, serviceDate);
  }

  runs(operator: string, trainNumber: string, since: string): RunRow[] {
    return this.db.prepare(`select * from runs where operator=? and train_number=? and service_date>=? order by service_date desc`)
      .all(operator, trainNumber, since) as unknown as RunRow[];
  }

  get(operator: string, trainNumber: string, serviceDate: string, source: RunSource): RunRow | undefined {
    return this.db.prepare(`select * from runs where operator=? and train_number=? and service_date=? and source=?`)
      .get(operator, trainNumber, serviceDate, source) as unknown as RunRow | undefined;
  }
}

/** On-time standard per railroad: Amtrak within 10 min, MTA's own 5:59, NJ Transit 5:59. */
export function onTimeThresholdSec(operator: string): number { return operator === 'amtrak' ? 600 : 359; }
