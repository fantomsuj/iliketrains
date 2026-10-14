// Dev check: compare the server's Amtrak positions with Amtraker's raw reports.
//   node scripts/check-positions.ts [http://localhost:8787]
import { haversine } from '../src/geo/geo.ts';
const base = process.argv[2] ?? 'http://localhost:8787';
const snap = await (await fetch(`${base}/api/snapshot`)).json();
const amt: Record<string, any> = {};
for (const v of Object.values(await (await fetch('https://api-v3.amtraker.com/v3/trains', { headers: { 'User-Agent': 'TrainsMVP-dev-check/0.1' } })).json()) as any[]) for (const t of v) amt[t.trainID] = t;
const rows: [number, string][] = [];
for (const t of snap.trains) {
  const a = t.operator === 'amtrak' ? amt[t.tripId] : null;
  if (!a || a.trainState !== 'Active') continue;
  const ageS = Math.round((snap.serverTime - Date.parse(a.lastValTS)) / 1000);
  rows.push([haversine([t.lon, t.lat], [a.lon, a.lat]), `${t.trainNumber} ${t.routeName} fix=${t.fix} speed=${t.speedMps}m/s report age=${ageS}s`]);
}
rows.sort((x, y) => x[0] - y[0]);
const q = (f: number) => Math.round(rows[Math.min(rows.length - 1, Math.floor(rows.length * f))][0]);
console.log(`${rows.length} active Amtrak trains; distance from our position now to the last raw report: median ${q(0.5)} m, p90 ${q(0.9)} m`);
console.log('largest:\n' + rows.slice(-5).map((r) => `  ${Math.round(r[0])} m  ${r[1]}`).join('\n'));
