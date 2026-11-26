// Service worker for the installed app.
//  - App shell (page, MapLibre, icons): precached per version, served cache-first, so the app opens offline.
//  - Track geometry, stations, map style: served from cache and refreshed in the background.
//  - Live snapshot and train/station details: network first; offline, the last copy, marked with its age.
//  - Base-map tiles, fonts and sprites: cached as you browse, capped so the cache stays small.
//  - PMTiles range requests and the live WebSocket pass straight through.
const VERSION = 'dev'; // build.mjs stamps a content hash here
const SHELL = `trains-shell-${VERSION}`, DATA = 'trains-data-v1', MAP = 'trains-map-v1';
const PRECACHE = [
  '/', '/config.js', '/manifest.webmanifest',
  '/vendor/maplibre-gl/dist/maplibre-gl.mjs', '/vendor/maplibre-gl/dist/maplibre-gl-worker.mjs',
  '/vendor/maplibre-gl/dist/maplibre-gl.css', '/vendor/pmtiles/dist/pmtiles.js', '/lib/motion.js',
  '/icons/icon.svg', '/icons/icon-192.png', '/icons/apple-touch-icon.png',
  '/figures/position-source.html', '/figures/position-source-light.html',
];
const LIMITS = { [DATA]: 400, [MAP]: 800 };

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(PRECACHE.map((u) => new Request(u, { cache: 'reload' })))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys.filter((k) => k.startsWith('trains-shell-') && k !== SHELL).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || req.headers.has('range')) return;
  const url = new URL(req.url);
  if (url.protocol !== 'https:' && url.protocol !== 'http:') return;
  const p = url.pathname;

  if (req.mode === 'navigate' && req.destination === 'document') { e.respondWith(networkFirst(req, SHELL, '/', 4000)); return; }
  if (url.origin === location.origin && !p.startsWith('/api/') && p !== '/style.json' && !p.startsWith('/tiles/') && !p.startsWith('/live')) {
    e.respondWith(cacheFirst(req, SHELL)); return;
  }
  if (p.startsWith('/live')) return; // SSE stream
  if (p === '/api/snapshot') { e.respondWith(snapshot(req)); return; }
  if (p === '/api/routes' || p === '/api/stations' || p.startsWith('/api/shapes/')) { e.respondWith(staleWhileRevalidate(req, DATA, e)); return; }
  if (p === '/style.json') { e.respondWith(networkFirst(req, DATA, null, 4000)); return; }
  if (/^\/api\/(trains|stations)\//.test(p) && !p.endsWith('/raw')) { e.respondWith(networkFirst(req, DATA, null, 6000)); return; }
  if (p.startsWith('/api/')) return;
  // base map: vector tiles, glyphs and sprites from the tile host, and z/x/y tiles from our server
  if (/\.(pbf|mvt|png|json|webp)$/.test(p) || url.hostname.includes('openfreemap') || p.startsWith('/tiles/')) { e.respondWith(staleWhileRevalidate(req, MAP, e)); return; }
});

async function cacheFirst(req, name) {
  const hit = await caches.match(req, { ignoreSearch: true });
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok) (await caches.open(name)).put(req, res.clone());
  return res;
}

async function networkFirst(req, name, fallbackUrl, timeoutMs) {
  const cache = await caches.open(name);
  try {
    const res = await withTimeout(fetch(req), timeoutMs);
    if (res.ok) { cache.put(fallbackUrl ?? req, res.clone()); trim(name); }
    return res;
  } catch (err) {
    const hit = (await cache.match(fallbackUrl ?? req)) ?? (fallbackUrl && await caches.match(fallbackUrl));
    if (hit) return hit;
    throw err;
  }
}

async function staleWhileRevalidate(req, name, e) {
  const cache = await caches.open(name);
  const hit = await cache.match(req);
  const refresh = fetch(req).then((res) => { if (res.ok) { cache.put(req, res.clone()); trim(name); } return res; });
  if (hit) { e.waitUntil(refresh.catch(() => {})); return hit; }
  return refresh;
}

// The live snapshot: always try the network. Offline, answer with the last one we saw and say when it was
// from (the page shows "offline, as of 7:41 PM" and does not animate trains forward from a stale clock).
async function snapshot(req) {
  const cache = await caches.open(DATA);
  try {
    const res = await withTimeout(fetch(req), 8000);
    if (res.ok) {
      const body = await res.clone().text();
      cache.put('/__last-snapshot', new Response(body, { headers: { 'Content-Type': 'application/json', 'X-Cached-At': String(Date.now()) } }));
    }
    return res;
  } catch (err) {
    const hit = await cache.match('/__last-snapshot');
    if (!hit) throw err;
    const snap = await hit.json();
    snap.__cachedAt = Number(hit.headers.get('X-Cached-At')) || Date.now();
    return new Response(JSON.stringify(snap), { headers: { 'Content-Type': 'application/json' } });
  }
}

function withTimeout(promise, ms) {
  return ms ? Promise.race([promise, new Promise((_, rej) => setTimeout(() => rej(new Error('timeout')), ms))]) : promise;
}

const trimming = {};
function trim(name) {
  if (trimming[name] || !LIMITS[name]) return;
  trimming[name] = setTimeout(async () => {
    delete trimming[name];
    const cache = await caches.open(name), keys = await cache.keys();
    for (const k of keys.slice(0, Math.max(0, keys.length - LIMITS[name]))) await cache.delete(k); // oldest first
  }, 5000);
}
