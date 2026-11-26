// Builds the installable web app into web/dist for static hosting (Vercel, or any CDN).
//
//   TRAINS_API_URL=https://trains-api.example.com node build.mjs
//
// The page, icons and figures are copied as they are; MapLibre and PMTiles come from node_modules;
// the shared motion model is type-stripped from the server's TypeScript source so the browser and
// the server animate trains with the same code; config.js points the page at the live server; the
// service worker gets a content hash so every deploy replaces the cached app shell.
import { createHash } from 'node:crypto';
import { cpSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import path from 'node:path';

const HERE = import.meta.dirname, OUT = path.join(HERE, 'dist');
const apiBase = (process.env.TRAINS_API_URL ?? '').trim().replace(/\/+$/, '');

if (apiBase && !/^https?:\/\/[^/]+/.test(apiBase)) throw new Error(`TRAINS_API_URL must be an absolute http(s) URL, got "${apiBase}"`);
if (!apiBase) {
  const msg = 'TRAINS_API_URL is not set: the app will look for the live server on its own origin.';
  // A production deploy without a server would publish a map with no trains; fail loudly instead.
  if (process.env.VERCEL_ENV === 'production') throw new Error(msg + ' Set it in the Vercel project (Settings > Environment Variables).');
  console.warn('warning: ' + msg);
}

rmSync(OUT, { recursive: true, force: true });
mkdirSync(OUT, { recursive: true });
const copy = (from, to = from) => cpSync(path.join(HERE, from), path.join(OUT, to), { recursive: true });
copy('index.html'); copy('manifest.webmanifest'); copy('icons'); copy('figures');

const mod = (pkg, file) => path.join(HERE, 'node_modules', pkg, file);
for (const f of ['maplibre-gl.mjs', 'maplibre-gl-worker.mjs', 'maplibre-gl.css'])
  cpSync(mod('maplibre-gl', 'dist/' + f), path.join(OUT, 'vendor/maplibre-gl/dist', f));
cpSync(mod('pmtiles', 'dist/pmtiles.js'), path.join(OUT, 'vendor/pmtiles/dist/pmtiles.js'));
for (const lic of [['maplibre-gl', 'LICENSE.txt'], ['pmtiles', 'LICENSE']]) {
  try { cpSync(mod(lic[0], lic[1]), path.join(OUT, 'vendor', lic[0], 'LICENSE.txt')); } catch { /* not every release ships one */ }
}

mkdirSync(path.join(OUT, 'lib'), { recursive: true });
writeFileSync(path.join(OUT, 'lib/motion.js'), stripTypeScriptTypes(readFileSync(path.join(HERE, '../server/src/motion.ts'), 'utf8')));
writeFileSync(path.join(OUT, 'config.js'), `window.TRAINS_CONFIG = ${JSON.stringify({ apiBase })};\n`);

// version = hash of everything the worker serves, so a deploy that changes nothing keeps the cache
const files = (dir) => readdirSync(dir).flatMap((f) => { const p = path.join(dir, f); return statSync(p).isDirectory() ? files(p) : [p]; });
const hash = createHash('sha256');
for (const f of files(OUT).sort()) hash.update(path.relative(OUT, f)).update(readFileSync(f));
const sw = readFileSync(path.join(HERE, 'sw.js'), 'utf8');
hash.update(sw);
const version = hash.digest('hex').slice(0, 12);
if (!sw.includes("const VERSION = 'dev';")) throw new Error('sw.js: VERSION marker not found');
writeFileSync(path.join(OUT, 'sw.js'), sw.replace("const VERSION = 'dev';", `const VERSION = '${version}';`));

console.log(`built web/dist (version ${version}, live server: ${apiBase || 'same origin'})`);
