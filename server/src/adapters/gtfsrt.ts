// GTFS-Realtime adapter used for LIRR, Metro-North and NJ Transit.
// Joins trip updates and vehicle positions to the static timetable to get the full stop list.
import G from 'gtfs-realtime-bindings';
import type { RawStop, RawTrain, Operator } from '../model.ts';
import { type GtfsFeed, type Trip, serviceDay } from '../gtfs.ts';
import type { AdapterContext, FeedAdapter } from './adapter.ts';
import type { FetchInit } from '../live/fetcher.ts';

const RT = G.transit_realtime;
/** Vehicle positions older than this are ignored; the train is placed from stop times instead. */
export const MAX_POSITION_AGE_MS = 5 * 60_000;

export type TripJoin = 'tripId' | 'trainNumber' | 'tripIdThenBlock';

export interface GtfsRtSource {
  /** Recording/cache key and URL for each request; a feed may need one or two requests. */
  requests(ctx: AdapterContext): Promise<{ key: string; url: string; init?: FetchInit }[]>;
}

export interface GtfsRtOptions {
  id: Operator; label: string; gtfs: GtfsFeed; join: TripJoin; source: GtfsRtSource;
  enabled?: boolean; disabledReason?: string;
}

type Entity = G.transit_realtime.IFeedEntity;

export class GtfsRtAdapter implements FeedAdapter {
  readonly id: Operator; readonly label: string; readonly enabled: boolean; readonly disabledReason?: string;
  private gtfs: GtfsFeed; private join: TripJoin; private source: GtfsRtSource;
  private byNumber = new Map<string, Trip[]>();

  constructor(o: GtfsRtOptions) {
    this.id = o.id; this.label = o.label; this.gtfs = o.gtfs; this.join = o.join; this.source = o.source;
    this.enabled = o.enabled ?? true; this.disabledReason = o.disabledReason;
    for (const t of o.gtfs.trips.values()) {
      for (const n of [t.shortName, t.blockId]) {
        if (!n) continue;
        const l = this.byNumber.get(n) ?? []; l.push(t); this.byNumber.set(n, l);
      }
    }
  }

  async poll(ctx: AdapterContext): Promise<RawTrain[]> {
    const entities: Entity[] = [];
    for (const r of await this.source.requests(ctx)) {
      const body = await ctx.fetcher.get(r.key, r.url, r.init);
      if (!body) continue;
      entities.push(...RT.FeedMessage.decode(body).entity);
    }
    return this.normalise(entities, ctx.clock.now());
  }

  /** Static trip for a realtime trip descriptor. */
  resolveTrip(tripId: string, number: string, startDate: string): Trip | undefined {
    if (this.join !== 'trainNumber') {
      const t = this.gtfs.trips.get(tripId);
      if (t) return t;
      if (this.join === 'tripId') return undefined;
    }
    const cands = this.byNumber.get(number) ?? [];
    return cands.find((t) => this.gtfs.runsOn(t.serviceId, startDate)) ?? cands[0];
  }

  normalise(entities: Entity[], now: number): RawTrain[] {
    const vehicles = new Map<string, G.transit_realtime.IVehiclePosition>();
    for (const e of entities) if (e.vehicle?.trip?.tripId) vehicles.set(e.vehicle.trip.tripId, e.vehicle);
    // MNR puts the vehicle in the same entity as the trip update, keyed by train number.
    for (const e of entities) if (e.vehicle && e.tripUpdate?.trip?.tripId) vehicles.set(e.tripUpdate.trip.tripId, e.vehicle);

    const out: RawTrain[] = [];
    for (const e of entities) {
      const tu = e.tripUpdate;
      if (!tu?.trip) continue;
      const tripId = tu.trip.tripId ?? e.id;
      const startDate = tu.trip.startDate || serviceDay(now).date;
      // MNR identifies trains by number in the entity id; elsewhere the entity id is an opaque key
      const number = e.vehicle?.vehicle?.label || (this.join === 'trainNumber' ? e.id ?? '' : '');
      const st = this.resolveTrip(tripId, number, startDate);
      const { midnight } = serviceDay(Date.UTC(+startDate.slice(0, 4), +startDate.slice(4, 6) - 1, +startDate.slice(6, 8), 16));
      const updates = tu.stopTimeUpdate ?? [];
      const byStop = new Map(updates.map((u) => [u.stopId ?? '', u]));
      const cancelled = tu.trip.scheduleRelationship === RT.TripDescriptor.ScheduleRelationship.CANCELED;

      const stops: RawStop[] = [];
      const stopIds = st ? st.stopIds : updates.map((u) => u.stopId ?? '');
      let delay: number | null = null, sawUpdate = false;
      stopIds.forEach((sid, i) => {
        const schArr = st ? midnight + st.arr[i] * 1000 : undefined;
        const schDep = st ? midnight + st.dep[i] * 1000 : undefined;
        const u = byStop.get(sid);
        let estArr: number | undefined, estDep: number | undefined;
        if (u) {
          sawUpdate = true;
          estArr = u.arrival?.time ? Number(u.arrival.time) * 1000 : undefined;
          estDep = u.departure?.time ? Number(u.departure.time) * 1000 : undefined;
          const dl = u.arrival?.delay ?? u.departure?.delay;
          if (dl != null) delay = dl;
          else if (estArr && schArr) delay = Math.round((estArr - schArr) / 1000);
          estArr ??= estDep; estDep ??= estArr;
        } else if (sawUpdate && delay != null) {
          // propagate the last known delay downstream
          estArr = schArr !== undefined ? schArr + delay * 1000 : undefined;
          estDep = schDep !== undefined ? schDep + delay * 1000 : undefined;
        }
        // stops before the first update are ones the train has already served
        const departed = !sawUpdate || (estDep ?? schDep ?? Infinity) < now;
        stops.push({ stationId: this.gtfs.stationOf(sid), name: this.gtfs.stops.get(this.gtfs.stationOf(sid))?.name,
          schArr, schDep, estArr, estDep, departed,
          skipped: u?.scheduleRelationship === RT.TripUpdate.StopTimeUpdate.ScheduleRelationship.SKIPPED });
      });
      if (!stops.length) continue;
      if (stops.every((s) => s.departed) && (stops[stops.length - 1].estArr ?? stops[stops.length - 1].schArr ?? 0) < now - 120_000) continue;

      const v = vehicles.get(tripId);
      const vAt = v?.timestamp ? Number(v.timestamp) * 1000 : 0;
      const position = v?.position && vAt && now - vAt < MAX_POSITION_AGE_MS
        ? { lat: v.position.latitude, lon: v.position.longitude, at: vAt, speedMps: v.position.speed ?? undefined } : undefined;
      const route = this.gtfs.routes.get(st?.routeId ?? tu.trip.routeId ?? '');
      out.push({
        tripId: st?.id ?? tripId, operator: this.id, route: route?.id ?? '', routeName: route?.longName || route?.shortName || '',
        trainNumber: st?.shortName || st?.blockId || number || 'Extra', // unscheduled extra train headsign: st?.headsign || stops[stops.length - 1].name,
        position, stops, delaySec: delay, source: 'live',
        updatedAt: Math.max(vAt, tu.timestamp ? Number(tu.timestamp) * 1000 : 0) || now,
        cancelled,
        shape: st ? { shapeId: st.shapeId, stations: st.stopIds.map((s) => this.gtfs.stationOf(s)) } : undefined,
        color: route ? `#${route.color}` : undefined,
      });
    }
    return out;
  }
}

/** Plain GET of one GTFS-RT URL (MTA feeds need no key). */
export const urlSource = (key: string, url: string): GtfsRtSource => ({ requests: async () => [{ key, url }] });

/**
 * NJ Transit rail GTFS-RT (developer portal). Needs NJT_API_TOKEN, or NJT_USERNAME + NJT_PASSWORD
 * to obtain one. Token endpoint and form fields follow NJT's published API; unverified without an account.
 */
export function njtSource(base: string, token: string, username: string, password: string): GtfsRtSource {
  let cached = token;
  return {
    async requests(ctx) {
      if (!cached) {
        const fd = new FormData(); fd.set('username', username); fd.set('password', password);
        const body = await ctx.fetcher.get('njt-token', `${base}/getToken`, { method: 'POST', body: fd, maxAgeMs: 12 * 3600_000 });
        cached = body ? (JSON.parse(body.toString('utf8')).UserToken ?? '') : '';
      }
      const form = () => { const f = new FormData(); f.set('token', cached); return f; };
      return [
        { key: 'njt-trips', url: `${base}/getTripUpdates`, init: { method: 'POST', body: form() } },
        { key: 'njt-vehicles', url: `${base}/getVehiclePositions`, init: { method: 'POST', body: form() } },
      ];
    },
  };
}
