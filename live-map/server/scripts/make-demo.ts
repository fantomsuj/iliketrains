// Cut a demo recording from raw feed captures (TRAINS_RECORD_DIR) and gzip it for the repo.
//   node scripts/make-demo.ts <rawDir> <outDir> <startHH:MM> <minutes>   (local New York time on the capture day)
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';

const [rawDir, outDir, start, minutes] = process.argv.slice(2);
if (!rawDir || !outDir || !start || !minutes) { console.error('usage: make-demo.ts <rawDir> <outDir> <HH:MM> <minutes>'); process.exit(1); }
const all = fs.readdirSync(rawDir).flatMap((k) => fs.readdirSync(path.join(rawDir, k)).map((f) => Number(f.split('.')[0])));
const day = new Date(Math.min(...all));
const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
let from = 0;
for (const t of [...new Set(all)].sort((a, b) => a - b)) {
  const p = Object.fromEntries(fmt.formatToParts(new Date(t)).map((x) => [x.type, x.value]));
  if (`${p.hour}:${p.minute}` >= start) { from = t; break; }
}
const to = from + Number(minutes) * 60_000;
let n = 0, bytes = 0;
for (const key of fs.readdirSync(rawDir)) {
  const files = fs.readdirSync(path.join(rawDir, key)).map((f) => ({ f, t: Number(f.split('.')[0]) })).filter((x) => x.t >= from && x.t <= to);
  fs.mkdirSync(path.join(outDir, key), { recursive: true });
  for (const { f, t } of files) {
    const gz = zlib.gzipSync(fs.readFileSync(path.join(rawDir, key, f)), { level: 9 });
    fs.writeFileSync(path.join(outDir, key, `${t}.bin.gz`), gz); n++; bytes += gz.length;
  }
}
fs.writeFileSync(path.join(outDir, 'README.md'), `# Demo recording\n\nRaw feed responses captured live on ${day.toISOString().slice(0, 10)}, ` +
  `${new Date(from).toISOString()} to ${new Date(to).toISOString()} (${minutes} min).\n` +
  `One folder per feed; each file is the gzipped response body, named by capture time (epoch ms).\n` +
  `Replay with \`TRAINS_DEMO=1 npm start\`. Sources: Amtraker v3 (unofficial), MTA LIRR and Metro-North GTFS-Realtime.\n`);
console.log(`wrote ${n} snapshots, ${(bytes / 1e6).toFixed(1)} MB, ${new Date(from).toISOString()} .. ${new Date(to).toISOString()}`);
