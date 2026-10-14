// Stations across all operators, grouped into hubs (New York Penn = Amtrak NYP + NJT + LIRR).
import { type LonLat, haversine } from '../geo/geo.ts';
import type { GtfsFeed } from '../gtfs.ts';
import { inRegion } from '../region.ts';

export interface StationEntry { key: string; operator: string; id: string; name: string; lonlat: LonLat }
export interface Hub { id: string; name: string; lonlat: LonLat; members: StationEntry[]; operators: string[] }

const OPERATOR_PRIORITY = ['amtrak', 'njt', 'lirr', 'mnr'];
const HUB_RADIUS_M = 350;

export function normaliseName(n: string): string {
  return n.toLowerCase().replace(/\b(amtrak|station|stn|rail|transportation center|terminal|nj transit)\b/g, ' ')
    .replace(/\bst\b\.?/g, 'street').replace(/\bpenn sta\b/g, 'penn').replace(/[^a-z0-9 ]/g, ' ').replace(/\s+/g, ' ').trim();
}
const tokens = (n: string) => new Set(normaliseName(n).split(' ').filter((w) => w.length > 2));

function nameOverlap(a: string, b: string): boolean {
  const ta = tokens(a), tb = tokens(b);
  for (const w of ta) if (tb.has(w)) return true;
  return false;
}

export class StationIndex {
  readonly hubs = new Map<string, Hub>();
  private hubByKey = new Map<string, string>();
  private names = new Map<string, string>();

  constructor(feeds: Map<string, GtfsFeed>) {
    const entries: StationEntry[] = [];
    for (const op of OPERATOR_PRIORITY) {
      const feed = feeds.get(op);
      if (!feed) continue;
      const used = new Set<string>();
      for (const t of feed.trips.values()) {
        if (feed.routes.get(t.routeId)?.type !== 2) continue;
        for (const s of t.stopIds) used.add(feed.stationOf(s));
      }
      for (const id of used) {
        const s = feed.stops.get(id);
        if (!s || !inRegion(s.lonlat)) continue;
        entries.push({ key: `${op}:${id}`, operator: op, id, name: s.name, lonlat: s.lonlat });
        this.names.set(`${op}:${id}`, s.name);
      }
    }
    // Greedy clustering in operator priority order: a station joins the first hub that is close
    // and shares a name word (or is very close), and has no member of the same operator yet.
    for (const e of entries) {
      let joined: Hub | undefined;
      for (const h of this.hubs.values()) {
        const dist = haversine(h.lonlat, e.lonlat);
        if (dist > HUB_RADIUS_M || h.operators.includes(e.operator)) continue;
        if (dist < 120 || h.members.some((m) => nameOverlap(m.name, e.name))) { joined = h; break; }
      }
      if (joined) { joined.members.push(e); joined.operators.push(e.operator); }
      else { joined = { id: e.key, name: e.name, lonlat: e.lonlat, members: [e], operators: [e.operator] }; this.hubs.set(e.key, joined); }
      this.hubByKey.set(e.key, joined.id);
    }
    for (const h of this.hubs.values()) h.name = displayName(h);
  }

  hubOf(operator: string, stationId: string): string { return this.hubByKey.get(`${operator}:${stationId}`) ?? `${operator}:${stationId}`; }
  name(operator: string, stationId: string): string { return this.names.get(`${operator}:${stationId}`) ?? stationId; }
  hub(id: string): Hub | undefined { return this.hubs.get(this.hubByKey.get(id) ?? id); }

  list() {
    return [...this.hubs.values()].map((h) => ({ id: h.id, name: h.name, lat: h.lonlat[1], lon: h.lonlat[0], operators: h.operators,
      code: h.members.find((m) => m.operator === 'amtrak')?.id }));
  }

  search(q: string, limit = 10) {
    const n = normaliseName(q);
    if (!n) return [];
    const scored = this.list().map((s) => {
      const name = normaliseName(s.name);
      const score = s.code?.toLowerCase() === q.toLowerCase() ? 0 : name.startsWith(n) ? 1 : name.includes(n) ? 2 : 9;
      return { s, score };
    }).filter((x) => x.score < 9).sort((a, b) => a.score - b.score || b.s.operators.length - a.s.operators.length);
    return scored.slice(0, limit).map((x) => x.s);
  }
}

/** Shortest sensible member name, preferring Amtrak's naming for shared stations. */
function displayName(h: Hub): string {
  const names = h.members.map((m) => m.name.replace(/\s+(Amtrak )?Station$/i, '').replace(/\s+/g, ' ').trim());
  return names.sort((a, b) => a.length - b.length)[0] ?? h.id;
}
