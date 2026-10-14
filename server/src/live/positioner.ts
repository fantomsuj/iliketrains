// RawTrain (what a feed says) -> TrainState (where it is along its track, and how it will move).
import { type LonLat, Polyline } from '../geo/geo.ts';
import type { GtfsFeed } from '../gtfs.ts';
import { type RouteIndex, type PatternRecord, orderedCoverage } from '../routes.ts';
import type { MotionPlan, PlanStop, RawStop, RawTrain, TrainState, TrainStop } from '../model.ts';
import { distanceAt } from '../motion.ts';
import { MAX_POSITION_AGE_MS } from '../adapters/gtfsrt.ts';

const MAX_SNAP_OFFSET_M = 1000;   // a reported position farther than this from the route is not trusted
const DEFAULT_SPEED = 20;         // m/s, ~45 mph, used when nothing better is known
/** Amtrak's GPS reports typically arrive 2-10 minutes late; an old fix plus dead reckoning still beats timetable-only. */
const MAX_POSITION_AGE_MS_BY_OPERATOR: Record<string, number> = { amtrak: 15 * 60_000 };

export interface StationLookup { hubOf(operator: string, stationId: string): string; name(operator: string, stationId: string): string }

export class Positioner {
  private routes: RouteIndex; private feeds: Map<string, GtfsFeed>; private stations: StationLookup;
  constructor(routes: RouteIndex, feeds: Map<string, GtfsFeed>, stations: StationLookup) {
    this.routes = routes; this.feeds = feeds; this.stations = stations;
  }

  /**
   * Route geometry for a live train. The timetable trip the adapter found is used when it serves
   * the live stop list in order; otherwise the best-covering pattern of the operator is used.
   */
  findPattern(raw: RawTrain): PatternRecord | undefined {
    const live = raw.stops.filter((s) => !s.skipped).map((s) => s.stationId);
    if (raw.shape) {
      const exact = this.routes.pattern(raw.operator, raw.shape.shapeId, raw.shape.stations);
      if (exact && orderedCoverage(live, exact.stops) >= 0.9) return exact;
    }
    const best = this.routes.bestCoverage(raw.operator, live);
    return best && best.coverage >= 0.5 ? best.pattern : undefined;
  }

  private stationCoord(operator: string, id: string): LonLat | undefined { return this.feeds.get(operator)?.stops.get(id)?.lonlat; }

  /** Distance along `line` of each raw stop, using the pattern where it matches and projection otherwise. */
  stopDistances(raw: RawTrain, line: Polyline, pattern?: PatternRecord): (number | null)[] {
    const out: (number | null)[] = [];
    let pi = 0, minD = 0;
    for (const s of raw.stops) {
      let d: number | null = null;
      if (pattern) {
        const j = pattern.stops.indexOf(s.stationId, pi);
        if (j >= 0) { d = pattern.dist[j]; pi = j + 1; }
      }
      if (d === null) {
        const c = this.stationCoord(raw.operator, s.stationId);
        if (c) { const r = line.project(c, minD, minD + 200_000); if (r.offset < 3000) d = r.d; }
      }
      if (d !== null) { d = Math.max(d, minD); minD = d; }
      out.push(d);
    }
    return out;
  }

  position(raw: RawTrain, now: number, previous?: TrainState): TrainState {
    const pattern = this.findPattern(raw);
    const line = pattern ? this.routes.line(pattern.shape) : undefined;
    const t = (s: RawStop, k: 'arr' | 'dep') => (k === 'arr' ? s.estArr ?? s.schArr ?? s.estDep ?? s.schDep : s.estDep ?? s.schDep ?? s.estArr ?? s.schArr) ?? null;
    const first = raw.stops[0], last = raw.stops[raw.stops.length - 1];
    const origin = first?.name ?? first?.stationId ?? '', destination = raw.headsign || last?.name || '';

    const base = {
      id: `${raw.operator}:${raw.tripId}`, operator: raw.operator, tripId: raw.tripId, trainNumber: raw.trainNumber,
      route: raw.route, routeName: raw.routeName, headsign: destination, color: raw.color ?? '#9aa5b1',
      delaySec: raw.delaySec, source: raw.source, origin, destination,
    };

    const dists = line ? this.stopDistances(raw, line, pattern) : raw.stops.map(() => null);
    const stops: TrainStop[] = raw.stops.map((s, i) => ({
      stationId: s.stationId, hubId: this.stations.hubOf(raw.operator, s.stationId),
      name: s.name ?? this.stations.name(raw.operator, s.stationId), d: Math.round(dists[i] ?? -1),
      schArr: s.schArr ?? null, schDep: s.schDep ?? null, estArr: s.estArr ?? null, estDep: s.estDep ?? null,
      status: s.skipped ? 'skipped' : s.departed ? 'departed' : 'upcoming', track: s.track,
    }));
    const nextIdx = raw.stops.findIndex((s) => !s.departed && !s.skipped);
    const next = nextIdx >= 0 ? { stationId: raw.stops[nextIdx].stationId, name: stops[nextIdx].name, eta: t(raw.stops[nextIdx], 'arr') } : null;
    const departedOrigin = raw.stops[0]?.departed || (first && (t(first, 'dep') ?? Infinity) < now);
    const finished = nextIdx < 0;

    let status: TrainState['status'] = raw.cancelled ? 'cancelled' : finished ? 'completed' : !departedOrigin ? 'scheduled' : 'enroute';

    // No route geometry: show the raw position (if any) and skip motion.
    if (!line) {
      const p = raw.position;
      return { ...base, fix: p ? 'gps' : raw.source === 'live' ? 'predicted' : 'timetable', shape: null, distM: 0, lat: p?.lat ?? NaN, lon: p?.lon ?? NaN, bearing: 0, speedMps: p?.speedMps ?? 0,
        status, updatedAt: raw.updatedAt, plan: null, progress: 0, next, stops };
    }

    // Distance from timetable (predicted where available) at time `now`.
    const known = raw.stops.map((s, i) => ({ s, d: dists[i] })).filter((x): x is { s: RawStop; d: number } => x.d !== null && !x.s.skipped);
    let lastDepartedD = known[0]?.d ?? 0, nextD = known[known.length - 1]?.d ?? line.length;
    for (const k of known) if (k.s.departed) lastDepartedD = k.d;
    for (const k of known) if (!k.s.departed && k.d >= lastDepartedD) { nextD = k.d; break; }
    // Feeds mark stops "departed" late, so a GPS fix may legitimately be one stop further on.
    const upcoming = known.filter((k) => !k.s.departed && k.d >= lastDepartedD);
    const gpsWindowEnd = (upcoming[1]?.d ?? line.length) + 3000;
    // upcoming stops we could not place (e.g. not in the timetable): the train may be anywhere ahead
    if (raw.stops.some((s, i) => !s.departed && dists[i] === null)) nextD = line.length;
    const timeD = (at: number): number => {
      let d = known[0]?.d ?? 0;
      for (let i = 0; i < known.length; i++) {
        const a = t(known[i].s, 'arr') ?? 0, l = t(known[i].s, 'dep') ?? a;
        if (at < a) {
          if (i === 0) return known[0].d;
          const pl = t(known[i - 1].s, 'dep') ?? 0;
          return pl >= a ? known[i].d : known[i - 1].d + ((known[i].d - known[i - 1].d) * (at - pl)) / (a - pl);
        }
        d = known[i].d;
        if (at <= l) return d;
      }
      return d;
    };

    let d0: number, t0: number, live = false;
    const p = raw.position;
    if (p && now - p.at < (MAX_POSITION_AGE_MS_BY_OPERATOR[raw.operator] ?? MAX_POSITION_AGE_MS) && departedOrigin) {
      const r = line.project([p.lon, p.lat], Math.max(0, lastDepartedD - 3000), nextD === line.length ? line.length : gpsWindowEnd);
      if (r.offset < MAX_SNAP_OFFSET_M) { d0 = r.d; t0 = p.at; live = true; }
    }
    if (!live) { t0 = now; d0 = departedOrigin ? Math.min(Math.max(timeD(now), lastDepartedD), nextD) : (known[0]?.d ?? 0); }
    // never move a train backward on the server either (small regressions are feed noise)
    if (previous?.plan && previous.shape === pattern!.shape) {
      const was = distanceAt(previous.plan, t0!);
      if (d0! < was && was - d0! < 3000) d0 = was;
    }

    // Upcoming stops as motion anchors.
    const planStops: PlanStop[] = [];
    for (const k of known) {
      if (k.s.departed || k.d < d0! - 1) continue;
      const arr = t(k.s, 'arr'), dep = t(k.s, 'dep');
      if (arr === null || dep === null) continue;
      planStops.push({ d: Math.round(k.d), arr, dep: Math.max(dep, arr) });
    }
    // Speed when a prediction is already overdue: the reported speed, else the scheduled pace of this leg.
    let fallbackSpeed = p?.speedMps && p.speedMps > 2 ? p.speedMps : 0;
    if (!fallbackSpeed) {
      const prevStop = [...known].reverse().find((k) => k.s.departed), nextStop = known.find((k) => !k.s.departed);
      if (prevStop && nextStop) {
        const dt = ((t(nextStop.s, 'arr') ?? 0) - (t(prevStop.s, 'dep') ?? 0)) / 1000;
        if (dt > 60) fallbackSpeed = (nextStop.d - prevStop.d) / dt;
      }
    }
    if (!(fallbackSpeed > 2)) fallbackSpeed = DEFAULT_SPEED;
    const maxD = nextD === line.length || !known.length ? line.length : known[known.length - 1].d;
    const plan: MotionPlan = { d0: Math.round(d0!), t0: t0!, fallbackSpeed: Math.round(fallbackSpeed * 10) / 10, stops: planStops, maxD: Math.round(maxD) };

    const dNow = distanceAt(plan, now);
    const pt = line.pointAt(dNow);
    const atStop = known.some((k) => Math.abs(k.d - dNow) < 150 && (t(k.s, 'arr') ?? Infinity) <= now + 30_000 && !k.s.departed);
    if (status === 'enroute' && atStop) status = 'atStation';
    const dOrigin = known[0]?.d ?? 0, dDest = known[known.length - 1]?.d ?? line.length;
    const speed = (distanceAt(plan, now + 10_000) - dNow) / 10;

    return { ...base, fix: live ? 'gps' : raw.source === 'live' ? 'predicted' : 'timetable',
      shape: pattern!.shape, distM: Math.round(dNow), lat: pt.lonlat[1], lon: pt.lonlat[0], bearing: Math.round(pt.bearing),
      speedMps: Math.round(speed * 10) / 10, status, updatedAt: live ? p!.at : raw.updatedAt, plan,
      progress: dDest > dOrigin ? Math.min(1, Math.max(0, (dNow - dOrigin) / (dDest - dOrigin))) : 0, next, stops };
  }
}
