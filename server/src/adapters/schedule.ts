// Timetable-only trains for feeds without realtime (e.g. NJ Transit when no API key is set).
// Positions come from the static schedule and are labelled source: "scheduled".
import type { RawTrain, Operator } from '../model.ts';
import { type GtfsFeed, type Trip, serviceDay } from '../gtfs.ts';
import type { AdapterContext, FeedAdapter } from './adapter.ts';

const LEAD_MS = 10 * 60_000;   // show a train this long before it departs its origin
const TAIL_MS = 2 * 60_000;    // and this long after it reaches its destination

export class ScheduleAdapter implements FeedAdapter {
  readonly id: Operator; readonly label: string; readonly enabled = true;
  private gtfs: GtfsFeed;
  private dayCache = new Map<string, Trip[]>();

  constructor(id: Operator, label: string, gtfs: GtfsFeed) { this.id = id; this.label = label; this.gtfs = gtfs; }

  private tripsOn(date: string): Trip[] {
    let l = this.dayCache.get(date);
    if (!l) {
      l = [...this.gtfs.trips.values()].filter((t) => t.stopIds.length > 1 && this.gtfs.routes.get(t.routeId)?.type === 2 && this.gtfs.runsOn(t.serviceId, date));
      this.dayCache.set(date, l);
      if (this.dayCache.size > 4) this.dayCache.delete(this.dayCache.keys().next().value!);
    }
    return l;
  }

  /** Trips in service at `now`, including yesterday's trips that run past midnight. */
  active(now: number): RawTrain[] {
    const out: RawTrain[] = [];
    for (const off of [0, -1]) {
      const { date, midnight } = serviceDay(now, off);
      for (const t of this.tripsOn(date)) {
        const start = midnight + t.dep[0] * 1000, end = midnight + t.arr[t.arr.length - 1] * 1000;
        if (now < start - LEAD_MS || now > end + TAIL_MS) continue;
        out.push(this.toRaw(t, date, midnight, now));
      }
    }
    return out;
  }

  toRaw(t: Trip, date: string, midnight: number, now: number): RawTrain {
    const route = this.gtfs.routes.get(t.routeId);
    const stops = t.stopIds.map((sid, i) => {
      const station = this.gtfs.stationOf(sid);
      const schArr = midnight + t.arr[i] * 1000, schDep = midnight + t.dep[i] * 1000;
      return { stationId: station, name: this.gtfs.stops.get(station)?.name, schArr, schDep, estArr: schArr, estDep: schDep, departed: schDep < now };
    });
    return {
      tripId: `${t.id}@${date}`, operator: this.id, route: t.routeId, routeName: route?.longName || route?.shortName || '',
      trainNumber: t.shortName || t.blockId || t.id, headsign: t.headsign || stops[stops.length - 1].name,
      stops, delaySec: null, source: 'scheduled', updatedAt: now,
      shape: { shapeId: t.shapeId, stations: t.stopIds.map((s) => this.gtfs.stationOf(s)) },
      color: route ? `#${route.color}` : undefined,
    };
  }

  async poll(ctx: AdapterContext): Promise<RawTrain[]> { return this.active(ctx.clock.now()); }
}
