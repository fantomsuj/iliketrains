// Polls every adapter, positions trains, emits events and pushes updates to clients.
import path from 'node:path';
import { config } from '../config.ts';
import { GtfsFeed, serviceDay } from '../gtfs.ts';
import type { RouteIndex } from '../routes.ts';
import type { LiveEvent, RawTrain, TrainState, TrainSummary } from '../model.ts';
import type { FeedAdapter } from '../adapters/adapter.ts';
import { AmtrakerAdapter } from '../adapters/amtraker.ts';
import { GtfsRtAdapter, njtSource, urlSource } from '../adapters/gtfsrt.ts';
import { ScheduleAdapter } from '../adapters/schedule.ts';
import { type Clock, type Fetcher, LiveFetcher, ReplayFetcher, realClock } from './fetcher.ts';
import { Positioner } from './positioner.ts';
import { StationIndex, tidyName } from './stations.ts';
import { EventLog, lateness, trainLabel } from './events.ts';
import { TrainTimeEquipment, POLL_MS as TRAINTIME_POLL_MS } from '../equipment/traintime.ts';
import { amtrakTypical } from '../equipment/models.ts';
import { HistoryStore } from '../history/store.ts';
import { ArchiveClient } from '../history/archive.ts';
import { HistoryRecorder, consistLabel } from '../history/recorder.ts';

export type Broadcast = (msg: { type: string; [k: string]: unknown }) => void;

interface AdapterHealth { id: string; label: string; enabled: boolean; note?: string; lastOk: number | null; lastError: string | null; trains: number }

const BOARD_PAST_MS = 20 * 60_000, BOARD_AHEAD_MS = 3 * 3600_000;
const capitalise = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export function summary(t: TrainState): TrainSummary {
  const { stops: _s, ...rest } = t;
  return rest.plan ? { ...rest, plan: { ...rest.plan, stops: rest.plan.stops.slice(0, 4) } } : rest;
}

export class Engine {
  readonly feeds = new Map<string, GtfsFeed>();
  readonly stations: StationIndex;
  readonly events = new EventLog();
  private adapters: FeedAdapter[] = [];
  private health_ = new Map<string, AdapterHealth>();
  private trains = new Map<string, TrainState>();
  private byAdapter = new Map<string, Set<string>>();
  private positioner: Positioner;
  private fetcher: Fetcher; readonly clock: Clock;
  private listeners: Broadcast[] = [];
  private routes: RouteIndex;
  private schedules = new Map<string, ScheduleAdapter>();
  private polledOnce = new Set<string>();
  readonly equipment: TrainTimeEquipment;
  readonly history: HistoryRecorder;

  constructor(routes: RouteIndex) {
    this.routes = routes;
    for (const id of ['amtrak', 'lirr', 'mnr', 'njt']) this.feeds.set(id, new GtfsFeed(id, path.join(config.gtfsDir, id)));
    this.stations = new StationIndex(this.feeds);
    this.positioner = new Positioner(routes, this.feeds, this.stations);
    if (config.demo) { const r = new ReplayFetcher(config.demoDir); this.fetcher = r; this.clock = r; }
    else { this.fetcher = new LiveFetcher(config.userAgent, config.recordDir); this.clock = realClock; }
    this.equipment = new TrainTimeEquipment(this.fetcher);
    this.history = new HistoryRecorder(new HistoryStore(config.demo ? path.join(config.dataDir, 'demo') : config.dataDir),
      config.demo ? null : new ArchiveClient(config.userAgent), this.feeds.get('amtrak')!);

    const f = (id: string) => this.feeds.get(id)!;
    const names: Record<string, string> = { amtrak: 'Amtrak', lirr: 'LIRR', mnr: 'Metro-North', njt: 'NJ Transit' };
    for (const id of ['amtrak', 'lirr', 'mnr', 'njt']) this.schedules.set(id, new ScheduleAdapter(id as never, `${names[id]} (timetable only)`, f(id)));
    this.adapters.push(new AmtrakerAdapter(config.amtrakerUrl, f('amtrak')));
    this.adapters.push(new GtfsRtAdapter({ id: 'lirr', label: 'LIRR (MTA GTFS-RT)', gtfs: f('lirr'), join: 'tripId', source: urlSource('lirr', config.mtaLirrUrl) }));
    this.adapters.push(new GtfsRtAdapter({ id: 'mnr', label: 'Metro-North (MTA GTFS-RT)', gtfs: f('mnr'), join: 'trainNumber', source: urlSource('mnr', config.mtaMnrUrl) }));
    const njtCreds = !!(config.njtToken || (config.njtUsername && config.njtPassword));
    const njtRecorded = this.fetcher instanceof ReplayFetcher && this.fetcher.has('njt-trips');
    if (config.demo ? njtRecorded : njtCreds) {
      this.adapters.push(new GtfsRtAdapter({ id: 'njt', label: 'NJ Transit (GTFS-RT)', gtfs: f('njt'), join: 'tripIdThenBlock',
        source: njtSource(config.njtBaseUrl, config.njtToken, config.njtUsername, config.njtPassword) }));
    } else {
      // No key: still show NJ Transit trains, positioned from the timetable and labelled "Scheduled".
      this.adapters.push(this.schedules.get('njt')!);
    }
    for (const a of this.adapters) this.health_.set(a.id, { id: a.id, label: a.label, enabled: a.enabled, note: a.disabledReason, lastOk: null, lastError: null, trains: 0 });
    if (config.demo ? !njtRecorded : !njtCreds) this.health_.get('njt')!.note = 'NJT_API_TOKEN or NJT_USERNAME+NJT_PASSWORD not set: positions from the timetable only';
  }

  onBroadcast(b: Broadcast) { this.listeners.push(b); }
  private emit(msg: { type: string; [k: string]: unknown }) { for (const l of this.listeners) l(msg); }

  start() {
    const eq = async () => { await this.equipment.poll(); setTimeout(eq, TRAINTIME_POLL_MS); };
    void eq();
    for (const a of this.adapters) {
      if (!a.enabled) continue;
      const interval = (a.id === 'amtrak' ? Math.max(30, config.pollSeconds) : config.pollSeconds) * 1000;
      const loop = async () => {
        try { await this.pollAdapter(a); } catch (e) { console.error(`[${a.id}] unexpected error:`, e); }
        setTimeout(loop, config.demo ? 5000 : interval);
      };
      void loop();
    }
  }

  /** One poll of one adapter; exposed for tests and the recorder. */
  async pollAdapter(a: FeedAdapter): Promise<void> {
    const h = this.health_.get(a.id)!;
    let raws: RawTrain[];
    try {
      raws = await a.poll({ fetcher: this.fetcher, clock: this.clock });
      h.lastOk = this.clock.now(); h.lastError = null;
    } catch (e) {
      h.lastError = String((e as Error).message ?? e);
      console.error(`[${a.id}] poll failed: ${h.lastError}`);
      return; // keep the last good state; clients keep dead-reckoning
    }
    this.ingest(a.id, raws);
  }

  ingest(adapterId: string, raws: RawTrain[]) {
    const now = this.clock.now();
    const quiet = !this.polledOnce.has(adapterId); this.polledOnce.add(adapterId);
    const seen = new Set<string>(); const changed: TrainSummary[] = []; const newEvents: LiveEvent[] = [];
    for (const raw of raws) {
      const id = `${raw.operator}:${raw.tripId}`;
      if (seen.has(id)) continue;
      const prev = this.trains.get(id);
      let next: TrainState;
      try { next = this.positioner.position(raw, now, prev); }
      catch (e) { console.error(`[${adapterId}] could not position ${id}:`, e); if (prev) seen.add(id); continue; }
      if (next.status === 'completed' || Number.isNaN(next.lat)) { this.recordRun(next); this.history.finish(next); this.trains.delete(id); continue; }
      seen.add(id);
      if (next.operator === 'lirr' || next.operator === 'mnr') {
        // posted tracks from the railroad's own app (the GTFS-RT feed rarely has them)
        const tracks = this.equipment.tracks(next.operator, next.trainNumber, next.serviceDate ?? undefined);
        for (const s of next.stops) { const tr = tracks.get(s.stationId); if (tr && !s.track) s.track = tr.track; }
      }
      this.recordRun(next);
      newEvents.push(...this.events.diff(prev, next, now, quiet));
      this.trains.set(id, next);
      changed.push(summary(next));
    }
    const removed: string[] = [];
    for (const id of this.byAdapter.get(adapterId) ?? []) if (!seen.has(id)) {
      const gone = this.trains.get(id);
      if (gone) this.history.finish(gone);
      this.trains.delete(id); removed.push(id);
    }
    this.byAdapter.set(adapterId, seen);
    this.health_.get(adapterId)!.trains = seen.size;
    this.emit({ type: 'trains', operator: adapterId, serverTime: now, trains: changed, removed });
    for (const e of newEvents) this.emit({ type: 'event', serverTime: now, event: e });
  }

  snapshot() {
    return { serverTime: this.clock.now(), demo: config.demo, trains: [...this.trains.values()].map(summary), events: this.events.recent(30) };
  }

  train(id: string): (TrainState & { equipment: unknown }) | undefined {
    const t = this.trains.get(id);
    if (!t) return undefined;
    return { ...t, equipment: this.equipmentFor(t) };
  }

  private recordRun(t: TrainState) {
    try {
      const c = t.operator === 'lirr' || t.operator === 'mnr' ? this.equipment.consist(t.operator, t.trainNumber, t.serviceDate ?? undefined) : null;
      this.history.record(t, consistLabel(c));
    } catch (e) { console.error('[history] record failed:', (e as Error).message); }
  }

  /** Live consist (LIRR, Metro-North) or the typical equipment for the service (Amtrak). */
  equipmentFor(t: TrainState) {
    if (t.operator === 'lirr' || t.operator === 'mnr') return this.equipment.consist(t.operator, t.trainNumber, t.serviceDate ?? undefined);
    if (t.operator === 'amtrak') { const e = amtrakTypical(t.routeName); return e ? { live: false as const, ...e } : null; }
    return { live: false as const, summary: 'Not published', detail: 'NJ Transit shares car details only with registered developers (NJT_* settings)', source: 'https://developer.njtransit.com/' };
  }

  health() {
    return { ok: true, demo: config.demo, serverTime: this.clock.now(), trains: this.trains.size, routesGeneratedAt: this.routes.file.generatedAt,
      equipment: { lastOk: this.equipment.lastOk || null, lastError: this.equipment.lastError },
      feeds: [...this.health_.values()], gtfs: [...this.feeds.values()].map((f) => ({ id: f.id, fetchedAt: f.fetchedAt })) };
  }

  search(q: string) {
    const s = q.trim().toLowerCase();
    if (!s) return { trains: [], stations: [] };
    const trains = [...this.trains.values()].filter((t) => t.trainNumber.toLowerCase() === s || t.trainNumber.toLowerCase().startsWith(s) ||
      `${trainLabel(t)} ${t.destination}`.toLowerCase().includes(s))
      .sort((a, b) => Number(b.trainNumber.toLowerCase() === s) - Number(a.trainNumber.toLowerCase() === s)).slice(0, 15).map(summary);
    return { trains, stations: this.stations.search(q) };
  }

  /** Departures and arrivals at a hub: live trains first-class, timetable fills the rest. */
  board(hubId: string) {
    const hub = this.stations.hub(hubId);
    if (!hub) return undefined;
    const now = this.clock.now();
    const memberKeys = new Set(hub.members.map((m) => `${m.operator}:${m.id}`));
    type Row = { trainId: string | null; operator: string; trainNumber: string; label: string; routeName: string; color: string;
      origin: string; destination: string; kind: 'departure' | 'arrival'; scheduled: number; estimated: number | null;
      delaySec: number | null; status: string; track: string | null; source: 'live' | 'scheduled'; fix: string };
    const rows: Row[] = [];
    const liveKeys = new Set<string>();
    for (const t of this.trains.values()) {
      t.stops.forEach((s, i) => {
        if (!memberKeys.has(`${t.operator}:${s.stationId}`)) return;
        const isLast = i === t.stops.length - 1;
        const sch = (isLast ? s.schArr : s.schDep) ?? s.schArr ?? s.schDep; const est = (isLast ? s.estArr : s.estDep) ?? null;
        if (sch === null) return;
        const when = est ?? sch;
        if (when < now - BOARD_PAST_MS || when > now + BOARD_AHEAD_MS) return;
        liveKeys.add(`${t.operator}:${t.trainNumber}`);
        const delay = est !== null ? Math.round((est - sch) / 1000) : t.delaySec;
        const status = t.status === 'cancelled' ? 'Cancelled' : s.status === 'skipped' ? 'Skips stop' : s.status === 'departed' ? (isLast ? 'Arrived' : 'Departed')
          : t.status === 'atStation' && t.next?.stationId === s.stationId ? 'Boarding' : t.source === 'scheduled' ? 'Scheduled' : capitalise(lateness(delay)) || 'Expected';
        rows.push({ trainId: t.id, operator: t.operator, trainNumber: t.trainNumber, label: trainLabel(t), routeName: t.routeName, color: t.color,
          origin: t.origin, destination: t.destination, kind: isLast ? 'arrival' : 'departure', scheduled: sch, estimated: est,
          delaySec: delay, status, track: s.track ?? null, source: t.source, fix: t.fix });
      });
    }
    // timetable rows for trains not (yet) in any live feed
    for (const m of hub.members) {
      const sched = this.schedules.get(m.operator)!;
      for (const off of [0, -1]) {
        const { date, midnight } = serviceDay(now, off);
        for (const raw of this.scheduledAt(sched, m.operator, m.id, date, midnight, now)) {
          if (liveKeys.has(`${raw.operator}:${raw.trainNumber}`)) continue;
          const idx = raw.stops.findIndex((s) => s.stationId === m.id);
          const s = raw.stops[idx]; const isLast = idx === raw.stops.length - 1;
          const sch = (isLast ? s.schArr : s.schDep)!;
          rows.push({ trainId: null, operator: raw.operator, trainNumber: raw.trainNumber, label: trainLabel(raw), routeName: raw.routeName,
            color: raw.color ?? '#9aa5b1', origin: tidyName(raw.stops[0].name ?? ''), destination: tidyName(raw.headsign ?? ''), kind: isLast ? 'arrival' : 'departure',
            scheduled: sch, estimated: null, delaySec: null, status: sch < now ? 'Departed' : 'Scheduled', track: null, source: 'scheduled', fix: 'timetable' });
          liveKeys.add(`${raw.operator}:${raw.trainNumber}`);
        }
      }
    }
    rows.sort((a, b) => (a.estimated ?? a.scheduled) - (b.estimated ?? b.scheduled));
    return { hub: { id: hub.id, name: hub.name, lat: hub.lonlat[1], lon: hub.lonlat[0], operators: hub.operators }, serverTime: now, rows };
  }

  private stationTrips = new Map<string, Map<string, number[]>>(); // operator -> station -> trip indexes
  private tripLists = new Map<string, ReturnType<GtfsFeed['trips']['get']>[]>();
  private scheduledAt(sched: ScheduleAdapter, op: string, stationId: string, date: string, midnight: number, now: number): RawTrain[] {
    const feed = this.feeds.get(op)!;
    if (!this.stationTrips.has(op)) {
      const list = [...feed.trips.values()]; this.tripLists.set(op, list);
      const idx = new Map<string, number[]>();
      list.forEach((t, i) => { for (const s of t!.stopIds) { const k = feed.stationOf(s); const l = idx.get(k) ?? []; l.push(i); idx.set(k, l); } });
      this.stationTrips.set(op, idx);
    }
    const out: RawTrain[] = [];
    for (const i of this.stationTrips.get(op)!.get(stationId) ?? []) {
      const t = this.tripLists.get(op)![i]!;
      if (feed.routes.get(t.routeId)?.type !== 2 || !feed.runsOn(t.serviceId, date)) continue;
      const j = t.stopIds.findIndex((s) => feed.stationOf(s) === stationId);
      const when = midnight + t.dep[j] * 1000;
      if (when < now - BOARD_PAST_MS || when > now + BOARD_AHEAD_MS) continue;
      out.push(sched.toRaw(t, date, midnight, now));
    }
    return out;
  }

  /** Route lines for the network map (computed offline by the route builder). */
  routeOverview() {
    return { license: this.routes.file.license,
      routes: this.routes.file.overview.map((o) => ({ ...o, polyline: this.routes.file.shapes[o.key].polyline })) };
  }
}
