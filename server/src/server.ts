// Trains live service: HTTP API, WebSocket + SSE push, tiles and the map style.
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { stripTypeScriptTypes } from 'node:module';
import { WebSocketServer, type WebSocket } from 'ws';
import { config } from './config.ts';
import { cors, safeJoin, sendFile, sendJson } from './http.ts';
import { RouteIndex } from './routes.ts';
import { Engine, type Broadcast } from './live/engine.ts';
import { TileServer } from './tiles.ts';

const routes = RouteIndex.load(config.routesFile);
const engine = new Engine(routes);

const tileServer = new TileServer(config.tilesFile);

/** The map style with URLs filled in. `?tiles=xyz` swaps the PMTiles source for this server's z/x/y endpoint. */
function styleJson(req: http.IncomingMessage, url: URL) {
  const host = req.headers['x-forwarded-host'] ?? req.headers.host ?? `localhost:${config.port}`;
  const proto = (req.headers['x-forwarded-proto'] as string) ?? 'http';
  const tiles = config.tilesUrl || `${proto}://${host}/tiles/trains.pmtiles`;
  const style = JSON.parse(fs.readFileSync(config.styleFile, 'utf8').replaceAll('{{TILES_URL}}', tiles).replaceAll('{{GLYPHS_URL}}', config.glyphsUrl));
  if (url.searchParams.get('tiles') === 'xyz') {
    const src = style.sources.trains;
    style.sources.trains = { type: 'vector', tiles: [`${proto}://${host}/tiles/{z}/{x}/{y}.mvt`], minzoom: 0, maxzoom: 14, attribution: src.attribution };
  }
  delete style.metadata;
  return JSON.stringify(style);
}

const sseClients = new Set<http.ServerResponse>();

const server = http.createServer((req, res) => {
  cors(res);
  if (req.method === 'OPTIONS') { res.writeHead(204).end(); return; }
  const url = new URL(req.url ?? '/', 'http://x');
  const p = url.pathname;
  try {
    if (p === '/health') return sendJson(res, 200, engine.health());
    if (p === '/style.json') { res.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }); res.end(styleJson(req, url)); return; }
    if (p === '/tiles/trains.pmtiles') return sendFile(req, res, config.tilesFile, 3600);
    if (p === '/api/snapshot') return sendJson(res, 200, engine.snapshot());
    if (p === '/api/events') return sendJson(res, 200, { events: engine.events.recent(100) });
    if (p === '/api/stations') return sendJson(res, 200, { stations: engine.stations.list() }, 3600);
    if (p === '/api/search') return sendJson(res, 200, engine.search(url.searchParams.get('q') ?? ''));
    if (p === '/api/routes') return sendJson(res, 200, engine.routeOverview(), 3600);
    let m;
    if ((m = /^\/tiles\/(\d+)\/(\d+)\/(\d+)\.mvt$/.exec(p))) {
      void tileServer.tile(Number(m[1]), Number(m[2]), Number(m[3])).then((t) => {
        if (!t) { res.writeHead(204).end(); return; }
        res.writeHead(200, { 'Content-Type': 'application/vnd.mapbox-vector-tile', 'Cache-Control': 'public, max-age=86400' }); res.end(t);
      }, (e) => sendJson(res, 500, { error: String(e) }));
      return;
    }
    if ((m = /^\/api\/shapes\/(.+)$/.exec(p))) {
      const key = decodeURIComponent(m[1]); const r = routes.file.shapes[key];
      return r ? sendJson(res, 200, { key, polyline: r.polyline, lengthM: r.lengthM, matchedFraction: r.matchedFraction }, 86400)
        : sendJson(res, 404, { error: 'unknown shape' });
    }
    if ((m = /^\/api\/trains\/(.+)$/.exec(p))) {
      const t = engine.train(decodeURIComponent(m[1]));
      return t ? sendJson(res, 200, t) : sendJson(res, 404, { error: 'unknown train' });
    }
    if ((m = /^\/api\/stations\/(.+)\/board$/.exec(p))) {
      const b = engine.board(decodeURIComponent(m[1]));
      return b ? sendJson(res, 200, b) : sendJson(res, 404, { error: 'unknown station' });
    }
    if (p === '/live/sse') {
      res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
      res.write(`event: snapshot\ndata: ${JSON.stringify(engine.snapshot())}\n\n`);
      sseClients.add(res); req.on('close', () => sseClients.delete(res));
      return;
    }
    // shared motion model for the web preview, type-stripped from the TypeScript source
    if (p === '/lib/motion.js') {
      res.writeHead(200, { 'Content-Type': 'text/javascript', 'Cache-Control': 'no-store' });
      res.end(stripTypeScriptTypes(fs.readFileSync(path.join(config.root, 'src/motion.ts'), 'utf8')));
      return;
    }
    // web preview (development aid; the product is the iOS app)
    if (p === '/' || p === '/preview') return sendFile(req, res, path.join(config.root, 'public/index.html'), 0);
    if (p.startsWith('/vendor/')) {
      const f = safeJoin(path.join(config.root, 'node_modules'), p.slice('/vendor/'.length));
      return f ? sendFile(req, res, f, 86400) : sendJson(res, 400, { error: 'bad path' });
    }
    const f = safeJoin(path.join(config.root, 'public'), p.slice(1));
    if (f && fs.existsSync(f)) return sendFile(req, res, f, 0);
    sendJson(res, 404, { error: 'not found' });
  } catch (e) {
    console.error(e);
    sendJson(res, 500, { error: String(e) });
  }
});

const wss = new WebSocketServer({ server, path: '/live' });
wss.on('connection', (ws: WebSocket) => { ws.send(JSON.stringify({ type: 'snapshot', ...engine.snapshot() })); });

const broadcast: Broadcast = (msg) => {
  const data = JSON.stringify(msg);
  for (const c of wss.clients) if (c.readyState === c.OPEN) c.send(data);
  for (const r of sseClients) r.write(`event: ${msg.type}\ndata: ${data}\n\n`);
};
engine.onBroadcast(broadcast);
setInterval(() => { for (const r of sseClients) r.write(': keepalive\n\n'); }, 15000).unref();

server.listen(config.port, config.host, () => {
  console.log(`trains server on ${config.host}:${config.port} (${config.demo ? 'demo replay of ' + config.demoDir : 'live feeds'})`);
  engine.start();
});
