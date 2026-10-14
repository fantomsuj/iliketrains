// Dev check: compare the server's positions with each feed's raw GPS reports.
//   node scripts/check-positions.ts [http://localhost:8787]
import G from 'gtfs-realtime-bindings';
import { haversine } from '../src/geo/geo.ts';
import { config } from '../src/config.ts';

const base = process.argv[2] ?? 'http://localhost:8787';
const snap = await (await fetch(`${base}/api/snapshot`)).json();
const ua = { headers: { 'User-Agent': 'TrainsMVP-dev-check/0.1' } };

// raw reports keyed by our train id
const raw = new Map<string, { lon: number; lat: number; at: number }>();
for (const v of Object.values(await (await fetch(config.amtrakerUrl, ua)).json()) as any[])
  for (const t of v) raw.set(`amtrak:${t.trainID}`, { lon: t.lon, lat: t.lat, at: Date.parse(t.lastValTS) });
const byNumber = new Map<string, string>(snap.trains.map((t: any) => [`${t.operator}#${t.trainNumber}`, t.id]));
for (const [op, url] of [['lirr', config.mtaLirrUrl], ['mnr', config.mtaMnrUrl]] as const) {
  const msg = G.transit_realtime.FeedMessage.decode(new Uint8Array(await (await fetch(url, ua)).arrayBuffer()));
  for (const e of msg.entity) {
    const v = e.vehicle; if (!v?.position) continue;
    const id = op === 'lirr' ? `lirr:${v.trip?.tripId}` : byNumber.get(`mnr#${v.vehicle?.label ?? e.id}`);
    if (id) raw.set(id, { lon: v.position.longitude, lat: v.position.latitude, at: Number(v.timestamp) * 1000 });
  }
}

for (const op of ['amtrak', 'lirr', 'mnr']) {
  const rows: [number, string][] = [];
  for (const t of snap.trains) {
    if (t.operator !== op || t.status === 'scheduled') continue;
    const r = raw.get(t.id); if (!r) continue;
    const age = Math.round((snap.serverTime - r.at) / 1000);
    if (age > 600) continue;
    rows.push([haversine([t.lon, t.lat], [r.lon, r.lat]), `${t.trainNumber} ${t.routeName} fix=${t.fix} ${t.speedMps}m/s report age=${age}s id=${t.id}`]);
  }
  if (!rows.length) continue;
  rows.sort((x, y) => x[0] - y[0]);
  const q = (f: number) => Math.round(rows[Math.min(rows.length - 1, Math.floor(rows.length * f))][0]);
  console.log(`${op}: ${rows.length} trains with a GPS report < 10 min old; our position now vs report: median ${q(0.5)} m, p90 ${q(0.9)} m`);
  for (const r of rows.slice(-3)) console.log(`    ${Math.round(r[0])} m  ${r[1]}`);
}
