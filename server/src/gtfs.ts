// Static GTFS loader. Reads the unpacked feed directories written by scripts/fetch-gtfs.sh.
import fs from 'node:fs';
import path from 'node:path';
import type { LonLat } from './geo/geo.ts';

export function parseCsv(text: string): Record<string, string>[] {
  const rows: string[][] = [];
  let row: string[] = [], field = '', q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { field += '"'; i++; } else q = false; }
      else field += c;
    } else if (c === '"') q = true;
    else if (c === ',') { row.push(field); field = ''; }
    else if (c === '\n' || c === '\r') {
      if (c === '\r' && text[i + 1] === '\n') i++;
      row.push(field); field = '';
      if (row.length > 1 || row[0] !== '') rows.push(row);
      row = [];
    } else field += c;
  }
  if (field !== '' || row.length) { row.push(field); rows.push(row); }
  const header = (rows.shift() ?? []).map((h) => h.replace(/^﻿/, '').trim());
  return rows.map((r) => Object.fromEntries(header.map((h, i) => [h, (r[i] ?? '').trim()])));
}

function readTable(dir: string, name: string): Record<string, string>[] {
  const p = path.join(dir, name);
  return fs.existsSync(p) ? parseCsv(fs.readFileSync(p, 'utf8')) : [];
}

/** "25:10:00" -> seconds after service-day midnight (may exceed 86400). */
export function gtfsTime(s: string): number {
  const [h, m, sec] = s.split(':').map(Number);
  return h * 3600 + m * 60 + (sec || 0);
}

export interface Stop { id: string; name: string; lonlat: LonLat; parent?: string; code?: string }
export interface Route { id: string; shortName: string; longName: string; color: string; textColor: string; type: number }
export interface Trip {
  id: string; routeId: string; serviceId: string; shapeId: string; headsign: string;
  shortName: string; directionId: string; blockId: string;
  stopIds: string[]; arr: number[]; dep: number[];
}

export class GtfsFeed {
  readonly stops = new Map<string, Stop>();
  readonly routes = new Map<string, Route>();
  readonly trips = new Map<string, Trip>();
  private calendar = new Map<string, { days: boolean[]; start: string; end: string }>();
  private calendarDates = new Map<string, Map<string, number>>(); // service -> date -> 1 add / 2 remove
  readonly fetchedAt: string;
  readonly id: string;
  readonly dir: string;

  constructor(id: string, dir: string) {
    this.id = id; this.dir = dir;
    this.fetchedAt = fs.existsSync(path.join(dir, '.fetched_at')) ? fs.readFileSync(path.join(dir, '.fetched_at'), 'utf8').trim() : '';
    for (const r of readTable(dir, 'stops.txt')) {
      this.stops.set(r.stop_id, { id: r.stop_id, name: r.stop_name, lonlat: [Number(r.stop_lon), Number(r.stop_lat)],
        parent: r.parent_station || undefined, code: r.stop_code || undefined });
    }
    for (const r of readTable(dir, 'routes.txt')) {
      this.routes.set(r.route_id, { id: r.route_id, shortName: r.route_short_name ?? '', longName: r.route_long_name ?? '',
        color: r.route_color || '888888', textColor: r.route_text_color || 'FFFFFF', type: Number(r.route_type) });
    }
    for (const r of readTable(dir, 'trips.txt')) {
      this.trips.set(r.trip_id, { id: r.trip_id, routeId: r.route_id, serviceId: r.service_id, shapeId: r.shape_id ?? '',
        headsign: r.trip_headsign ?? '', shortName: r.trip_short_name ?? '', directionId: r.direction_id ?? '', blockId: r.block_id ?? '',
        stopIds: [], arr: [], dep: [] });
    }
    const st = readTable(dir, 'stop_times.txt');
    st.sort((a, b) => (a.trip_id < b.trip_id ? -1 : a.trip_id > b.trip_id ? 1 : Number(a.stop_sequence) - Number(b.stop_sequence)));
    for (const r of st) {
      const t = this.trips.get(r.trip_id);
      if (!t) continue;
      t.stopIds.push(r.stop_id);
      t.arr.push(gtfsTime(r.arrival_time || r.departure_time));
      t.dep.push(gtfsTime(r.departure_time || r.arrival_time));
    }
    for (const r of readTable(dir, 'calendar.txt')) {
      const days = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'].map((d) => r[d] === '1');
      this.calendar.set(r.service_id, { days, start: r.start_date, end: r.end_date });
    }
    for (const r of readTable(dir, 'calendar_dates.txt')) {
      let m = this.calendarDates.get(r.service_id);
      if (!m) { m = new Map(); this.calendarDates.set(r.service_id, m); }
      m.set(r.date, Number(r.exception_type));
    }
  }

  /** Raw shapes.txt, loaded on demand (only the route builder needs it). */
  loadShapes(): Map<string, LonLat[]> {
    const pts = new Map<string, { seq: number; p: LonLat }[]>();
    for (const r of readTable(this.dir, 'shapes.txt')) {
      let a = pts.get(r.shape_id);
      if (!a) { a = []; pts.set(r.shape_id, a); }
      a.push({ seq: Number(r.shape_pt_sequence), p: [Number(r.shape_pt_lon), Number(r.shape_pt_lat)] });
    }
    const out = new Map<string, LonLat[]>();
    for (const [id, a] of pts) out.set(id, a.sort((x, y) => x.seq - y.seq).map((x) => x.p));
    return out;
  }

  /** Is the service running on a date (YYYYMMDD, local service day)? */
  runsOn(serviceId: string, date: string): boolean {
    const ex = this.calendarDates.get(serviceId)?.get(date);
    if (ex === 1) return true;
    if (ex === 2) return false;
    const c = this.calendar.get(serviceId);
    if (!c || date < c.start || date > c.end) return false;
    const d = new Date(`${date.slice(0, 4)}-${date.slice(4, 6)}-${date.slice(6, 8)}T12:00:00Z`);
    return c.days[d.getUTCDay()];
  }

  /** Station-level id: the parent station when the feed uses platforms. */
  stationOf(stopId: string): string { return this.stops.get(stopId)?.parent || stopId; }
}

const NY_TZ = 'America/New_York';

/** Local calendar date (YYYYMMDD) and the epoch of local midnight for a service day. */
export function serviceDay(epochMs: number, offsetDays = 0): { date: string; midnight: number } {
  const d = new Date(epochMs + offsetDays * 86400000);
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: NY_TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(d);
  const get = (t: string) => parts.find((p) => p.type === t)!.value;
  const date = `${get('year')}${get('month')}${get('day')}`;
  // GTFS times are measured from "noon minus 12h", which equals local midnight except on DST days.
  const noonUtcGuess = Date.UTC(Number(get('year')), Number(get('month')) - 1, Number(get('day')), 12);
  const offsetMin = tzOffsetMinutes(noonUtcGuess);
  const midnight = noonUtcGuess - offsetMin * 60000 - 12 * 3600000;
  return { date, midnight };
}

function tzOffsetMinutes(epochMs: number): number {
  const s = new Intl.DateTimeFormat('en-US', { timeZone: NY_TZ, timeZoneName: 'shortOffset' }).format(new Date(epochMs));
  const m = /GMT([+-]\d+)(?::(\d+))?/.exec(s);
  if (!m) return 0;
  const h = Number(m[1]);
  return h * 60 + Math.sign(h) * Number(m[2] ?? 0);
}
