// Amtrak via the unofficial Amtraker v3 API (https://github.com/piemadd/amtraker-v3).
// Designed so the URL can point at a self-hosted Amtraker instance later (AMTRAKER_URL).
import type { RawStop, RawTrain } from '../model.ts';
import type { GtfsFeed, Trip } from '../gtfs.ts';
import { orderedCoverage } from '../routes.ts';
import { inRegion } from '../region.ts';
import type { AdapterContext, FeedAdapter } from './adapter.ts';

interface AmtrakerStation {
  name: string; code: string; schArr?: string; schDep?: string; arr?: string; dep?: string;
  status: 'Departed' | 'Enroute' | 'Station' | string; platform?: string; bus?: boolean;
}
interface AmtrakerTrain {
  routeName: string; trainNum: string; trainID: string; lat: number; lon: number; heading: string;
  stations: AmtrakerStation[]; trainState: string; velocity: number; lastValTS: string; updatedAt: string;
  provider: string; iconColor?: string; destName: string; origName: string;
}

const ms = (s?: string) => (s ? Date.parse(s) : undefined);
const MPH = 0.44704;

export class AmtrakerAdapter implements FeedAdapter {
  readonly id = 'amtrak';
  readonly label = 'Amtrak (Amtraker)';
  readonly enabled = true;
  private byNumber = new Map<string, Trip[]>();
  private url: string; private gtfs: GtfsFeed;

  constructor(url: string, gtfs: GtfsFeed) {
    this.url = url; this.gtfs = gtfs;
    for (const t of gtfs.trips.values()) {
      if (gtfs.routes.get(t.routeId)?.type !== 2) continue;
      const list = this.byNumber.get(t.shortName) ?? [];
      list.push(t); this.byNumber.set(t.shortName, list);
    }
  }

  /** The static trip with this train number whose station list best matches the live one. */
  private staticTrip(num: string, codes: string[]): Trip | undefined {
    const cands = this.byNumber.get(num);
    if (!cands?.length) return undefined;
    let best: Trip | undefined, bestScore = -1;
    for (const t of cands) {
      const stations = t.stopIds.map((s) => this.gtfs.stationOf(s));
      // order matters: the same number can appear on both directions in the timetable
      const score = orderedCoverage(codes, stations) - 0.001 * Math.abs(stations.length - codes.length);
      if (score > bestScore) { bestScore = score; best = t; }
    }
    return best;
  }

  async poll(ctx: AdapterContext): Promise<RawTrain[]> {
    const body = await ctx.fetcher.get('amtraker', this.url);
    if (!body) return [];
    const data = JSON.parse(body.toString('utf8')) as Record<string, AmtrakerTrain[]>;
    const out: RawTrain[] = [];
    for (const list of Object.values(data)) for (const t of list) {
      if (t.provider !== 'Amtrak' || t.trainState === 'Completed') continue;
      const stations = t.stations.filter((s) => !s.bus);
      const touchesRegion = stations.some((s) => {
        const st = this.gtfs.stops.get(s.code);
        return st ? inRegion(st.lonlat) : false;
      }) || inRegion([t.lon, t.lat]);
      if (!touchesRegion) continue;

      const stops: RawStop[] = stations.map((s) => ({
        stationId: s.code, name: s.name,
        schArr: ms(s.schArr), schDep: ms(s.schDep), estArr: ms(s.arr), estDep: ms(s.dep),
        departed: s.status === 'Departed', track: s.platform || undefined,
      }));
      const next = stations.findIndex((s) => s.status !== 'Departed');
      const ref = next >= 0 ? stops[next] : stops[stops.length - 1];
      const sch = ref?.schArr ?? ref?.schDep, est = ref?.estArr ?? ref?.estDep;
      const st = this.staticTrip(t.trainNum, stations.map((s) => s.code));
      const lastSeen = ms(t.lastValTS) ?? ms(t.updatedAt) ?? ctx.clock.now();
      out.push({
        tripId: t.trainID, operator: 'amtrak', route: t.routeName, routeName: t.routeName,
        trainNumber: t.trainNum, headsign: t.destName,
        position: t.trainState === 'Predeparture' ? undefined : { lat: t.lat, lon: t.lon, at: lastSeen, speedMps: (t.velocity || 0) * MPH },
        stops, delaySec: sch !== undefined && est !== undefined ? Math.round((est - sch) / 1000) : null,
        source: 'live', updatedAt: lastSeen,
        shape: st ? { shapeId: st.shapeId, stations: st.stopIds.map((s) => this.gtfs.stationOf(s)) } : undefined,
        color: '#4a90d9',
      });
    }
    return out;
  }
}
