// Serves web/dist the way Vercel will (static files, index.html at /), for checking a build locally:
//   TRAINS_API_URL=http://localhost:8787 npm run preview   ->  http://localhost:4173
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.join(import.meta.dirname, 'dist'), PORT = Number(process.env.PORT ?? 4173);
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml', '.txt': 'text/plain' };
http.createServer((req, res) => {
  const p = new URL(req.url, 'http://x').pathname;
  let f = path.join(ROOT, path.posix.normalize(p));
  if (!f.startsWith(ROOT)) { res.writeHead(400).end(); return; }
  if (fs.existsSync(f) && fs.statSync(f).isDirectory()) f = path.join(f, 'index.html');
  if (!fs.existsSync(f)) { res.writeHead(404).end('not found'); return; }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] ?? 'application/octet-stream', 'Cache-Control': 'no-cache' });
  fs.createReadStream(f).pipe(res);
}).listen(PORT, () => console.log(`web/dist on http://localhost:${PORT}`));
