// Runtime configuration, all from environment variables (see README "Environment").
import path from 'node:path';

const ROOT = path.resolve(import.meta.dirname, '..');
const env = process.env;

export const config = {
  root: ROOT,
  port: Number(env.PORT ?? 8787),
  /** Interface to listen on; 127.0.0.1 behind a proxy, 0.0.0.0 to reach it from a phone on the LAN. */
  host: env.HOST ?? '0.0.0.0',
  /** Replay recorded feed snapshots instead of polling (TRAINS_DEMO=1, optional TRAINS_DEMO_DIR). */
  demo: env.TRAINS_DEMO === '1' || env.TRAINS_DEMO === 'true',
  demoDir: env.TRAINS_DEMO_DIR ?? path.join(ROOT, 'data/demo/2026-10-14-evening'),
  /** Record every raw feed response to this directory while running live. */
  recordDir: env.TRAINS_RECORD_DIR ?? '',
  pollSeconds: Number(env.POLL_SECONDS ?? 20),
  userAgent: env.TRAINS_USER_AGENT ?? 'TrainsMVP/0.1 (+contact: set TRAINS_USER_AGENT)',
  amtrakerUrl: env.AMTRAKER_URL ?? 'https://api-v3.amtraker.com/v3/trains',
  mtaLirrUrl: env.MTA_LIRR_URL ?? 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/lirr%2Fgtfs-lirr',
  mtaMnrUrl: env.MTA_MNR_URL ?? 'https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/mnr%2Fgtfs-mnr',
  /** NJ Transit GTFS-RT. Either a ready token (NJT_API_TOKEN) or developer-portal credentials. */
  njtToken: env.NJT_API_TOKEN ?? '',
  njtUsername: env.NJT_USERNAME ?? '',
  njtPassword: env.NJT_PASSWORD ?? '',
  njtBaseUrl: env.NJT_BASE_URL ?? 'https://raildata.njtransit.com/api/GTFSRT',
  /** Public URL of the PMTiles archive (a CDN in production); defaults to this server. */
  tilesUrl: env.TILES_URL ?? '',
  glyphsUrl: env.GLYPHS_URL ?? 'https://protomaps.github.io/basemaps-assets/fonts/{fontstack}/{range}.pbf',
  tilesFile: env.TILES_FILE ?? path.resolve(ROOT, '../tiles/dist/trains.pmtiles'),
  styleFile: path.resolve(ROOT, '../tiles/style/trains-dark.json'),
  routesFile: env.ROUTES_FILE ?? path.join(ROOT, 'data/derived/routes.json'),
  /** Run history database and other state the server writes. */
  dataDir: env.TRAINS_DATA_DIR ?? path.join(ROOT, 'data/state'),
  gtfsDir: path.join(ROOT, 'data/gtfs'),
};
