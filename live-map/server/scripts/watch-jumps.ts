// Dev check: watch the live stream and report trains whose position jumps by more than 2 km
// between consecutive updates (relative to where the previous plan said they would be).
//   node scripts/watch-jumps.ts [seconds=180] [ws://localhost:8787/live]
import WebSocket from 'ws';
import { distanceAt } from '../src/motion.ts';
const secs = Number(process.argv[2] ?? 180), url = process.argv[3] ?? 'ws://localhost:8787/live';
const last = new Map<string, any>();
let updates = 0, jumps = 0;
const ws = new WebSocket(url);
ws.on('message', (data) => {
  const m = JSON.parse(String(data));
  const list = m.type === 'snapshot' ? m.trains : m.type === 'trains' ? m.trains : [];
  for (const t of list) {
    const p = last.get(t.id);
    if (p && p.plan && t.plan && p.shape === t.shape) {
      updates++;
      const expected = distanceAt(p.plan, t.plan.t0), got = t.plan.d0;
      if (Math.abs(got - expected) > 2000) {
        jumps++;
        console.log(`${t.id} #${t.trainNumber} ${t.routeName}: ${p.fix}->${t.fix} expected ${Math.round(expected)} got ${Math.round(got)} (${Math.round((got - expected) / 1000)} km)`);
      }
    }
    last.set(t.id, t);
  }
});
setTimeout(() => { console.log(`${updates} consecutive updates compared, ${jumps} jumps > 2 km`); process.exit(0); }, secs * 1000);
