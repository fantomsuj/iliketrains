// Small HTTP helpers: JSON responses, static files with Range support (PMTiles needs it).
import fs from 'node:fs';
import path from 'node:path';
import zlib from 'node:zlib';
import type { IncomingMessage, ServerResponse } from 'node:http';

const TYPES: Record<string, string> = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css',
  '.json': 'application/json', '.pmtiles': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml',
  '.map': 'application/json', '.webmanifest': 'application/manifest+json', '.txt': 'text/plain; charset=utf-8',
};

/** True when a browser on `origin` may use the API. No list configured, or no Origin header (curl, the iOS app): yes. */
export function originAllowed(origin: string | undefined, allowed: string[]): boolean {
  return !origin || allowed.length === 0 || allowed.includes(origin);
}

export function cors(res: ServerResponse, origin?: string, allowed: string[] = []) {
  if (allowed.length === 0) res.setHeader('Access-Control-Allow-Origin', '*');
  else { res.setHeader('Vary', 'Origin'); if (origin && allowed.includes(origin)) res.setHeader('Access-Control-Allow-Origin', origin); }
  res.setHeader('Access-Control-Allow-Headers', 'Range');
  res.setHeader('Access-Control-Expose-Headers', 'Content-Range, Content-Length, ETag');
}

export function sendJson(res: ServerResponse, status: number, body: unknown, maxAge = 0) {
  const data = JSON.stringify(body);
  const headers: Record<string, string> = { 'Content-Type': 'application/json', 'Cache-Control': maxAge ? `public, max-age=${maxAge}` : 'no-store', Vary: 'Accept-Encoding' };
  // the snapshot and route geometry are a few hundred kB of JSON and shrink ~8x; phones on cellular notice
  if (data.length > 1024 && /\bgzip\b/.test(String(res.req?.headers['accept-encoding'] ?? ''))) {
    res.writeHead(status, { ...headers, 'Content-Encoding': 'gzip' });
    res.end(zlib.gzipSync(data, { level: 6 }));
    return;
  }
  res.writeHead(status, headers);
  res.end(data);
}

export function sendFile(req: IncomingMessage, res: ServerResponse, file: string, maxAge = 300): void {
  let st: fs.Stats;
  try { st = fs.statSync(file); } catch { res.writeHead(404).end('not found'); return; }
  if (!st.isFile()) { res.writeHead(404).end('not found'); return; }
  const type = TYPES[path.extname(file)] ?? 'application/octet-stream';
  const etag = `"${st.size.toString(16)}-${st.mtimeMs.toString(16)}"`;
  const headers: Record<string, string | number> = { 'Content-Type': type, 'Accept-Ranges': 'bytes', ETag: etag, 'Cache-Control': `public, max-age=${maxAge}` };
  const range = req.headers.range && /^bytes=(\d*)-(\d*)$/.exec(req.headers.range);
  if (range) {
    const start = range[1] ? Number(range[1]) : st.size - Number(range[2]);
    const end = range[1] && range[2] ? Math.min(Number(range[2]), st.size - 1) : st.size - 1;
    if (start > end || start >= st.size) { res.writeHead(416, { 'Content-Range': `bytes */${st.size}` }).end(); return; }
    res.writeHead(206, { ...headers, 'Content-Range': `bytes ${start}-${end}/${st.size}`, 'Content-Length': end - start + 1 });
    fs.createReadStream(file, { start, end }).pipe(res);
    return;
  }
  res.writeHead(200, { ...headers, 'Content-Length': st.size });
  if (req.method === 'HEAD') { res.end(); return; }
  fs.createReadStream(file).pipe(res);
}

/** Resolve `rel` under `root`, refusing paths that escape it. */
export function safeJoin(root: string, rel: string): string | null {
  const p = path.resolve(root, '.' + path.posix.normalize('/' + rel));
  return p.startsWith(path.resolve(root) + path.sep) || p === path.resolve(root) ? p : null;
}
