# Deploying the live map for public use

Two pieces, two hosts:

| Piece | Where | Why |
|---|---|---|
| **Web app** (`web/`): the map, installable as a PWA | **Vercel** (static) | Global CDN, free tier, preview URL for every branch |
| **Live server** (`server/`): polls the railroads, places trains on track, pushes updates | **Railway** (one always-on container) | It is a long-running process: polling loop, WebSocket push, ~100 MB of timetables in memory, a SQLite history file. Vercel functions are short-lived and can't hold any of that. |
| **Rail tiles** (`tiles/dist/trains.pmtiles`, ~23 MB) | Any CDN with range requests + CORS (Cloudflare R2 recommended) | Read directly by the browser; keeps tile traffic off the server |

The street base map comes from OpenFreeMap (no key) and needs nothing from you.

```
browser / installed PWA ── static app ──────────► Vercel
        │ ── /api/*, /style.json, wss://…/live ─► Railway (live server) ─► Amtraker, MTA, NJ Transit, TrainTime
        └─ ── pmtiles range requests ───────────► R2 / CDN
```

## 1. Live server on Railway

1. In Railway: **New Project → Deploy from GitHub repo →** this repository.
2. Service **Settings**:
   - **Root Directory**: `live-map`
   - **Config-as-code file**: `/live-map/railway.json` (Railway does not look inside the root directory for it on its own)
   - Railway then builds `live-map/Dockerfile`. The image downloads the four railroads' static timetables during the build.
3. **Volumes → New volume**, mount path `/data`. The run history (`history.sqlite`) lives there and survives redeploys.
4. **Variables**:

   | Variable | Value |
   |---|---|
   | `TRAINS_USER_AGENT` | `ILikeTrains/1.0 (+mailto:you@example.com)`. Required in spirit: Amtraker, MTA and NJ Transit should be able to reach you |
   | `ALLOWED_ORIGINS` | `https://<your-vercel-app>.vercel.app` (add your custom domain later, comma-separated) |
   | `TILES_URL` | public URL of `trains.pmtiles` once uploaded (step 3) |
   | `NJT_API_TOKEN`, or `NJT_USERNAME` + `NJT_PASSWORD` | optional; without them NJ Transit is shown from the timetable as "Scheduled" |

   Railway sets `PORT` itself; the server reads it.
5. **Networking → Generate Domain**. Check `https://<service>.up.railway.app/health`: every feed should show a recent `lastOk`.
6. Keep **one replica**. Each replica polls the feeds and keeps its own trains in memory; two replicas double the polling and give clients slightly different events.

Timetables change: redeploy about weekly (Railway: *Redeploy*, or a scheduled GitHub Action calling the Railway API) so the image fetches fresh GTFS.

Size: the demo replay with two of four timetables used ~480 MB RAM; budget **1 GB**.

## 2. Web app on Vercel

1. **Add New → Project →** import this repository. Leave the root directory as the repository root: `vercel.json` there already sets install, build and output (`live-map/web/dist`) and skips builds for commits that don't touch the web app.
2. **Environment Variables**: `TRAINS_API_URL` = the Railway URL from step 1 (e.g. `https://trains-live.up.railway.app`). A production build fails on purpose without it, so a map with no trains never ships.
3. Deploy, then add that `*.vercel.app` URL to `ALLOWED_ORIGINS` on Railway.

Preview deployments for other branches build without `TRAINS_API_URL` too (with a warning). They need the variable for the Preview environment, and their URLs in `ALLOWED_ORIGINS`, to show trains. Simplest: leave `ALLOWED_ORIGINS` unset while testing (any origin may read the API; it is read-only).

Local check of a production build: `cd web && npm ci && TRAINS_API_URL=http://localhost:8787 npm run preview` with the server running (`cd server && npm run demo`).

## 3. Rail tiles

`tiles/build.sh` (needs osmium-tool, Java 21, Node 22; downloads ~2 GB of OpenStreetMap extracts) writes `tiles/dist/trains.pmtiles`. Upload it to Cloudflare R2 (no egress fees) or Vercel Blob, with:

- public access,
- CORS allowing `GET` and `HEAD` from your app's origin, with the `Range` request header and the `Content-Range`, `Content-Length` and `ETag` response headers exposed.

Set `TILES_URL` on Railway to the file's public URL. Without it the map still works (base map from OpenFreeMap, route lines and trains from the server) but the dedicated rail detail layers (tracks, yards, platforms) are empty.

## 4. Custom domain (optional)

- Vercel: **Settings → Domains**, add e.g. `trains.example.com`.
- Railway: **Settings → Networking → Custom Domain**, add e.g. `live.trains.example.com` (a CNAME at your DNS provider).
- Update `TRAINS_API_URL` on Vercel (and redeploy) and `ALLOWED_ORIGINS` on Railway.

Keeping the app and server on one registrable domain also makes the WebSocket less likely to be blocked by strict networks and content blockers.

## The PWA

- **Install**: Chrome, Edge and Android show an "Install" card (from `beforeinstallprompt`). iOS Safari has no such event, so iPhone and iPad visitors get a one-time hint: Share → Add to Home Screen. Dismissing either hides it for 30 days.
- **Offline**: the app shell, MapLibre and icons are precached, so the installed app opens without a connection. Route lines, stations and visited map tiles are cached as they are used (capped at ~400 API responses and ~800 tiles). Offline, the map shows the last trains it saw, frozen in place, and the status pill reads "offline, as of 7:41 PM"; it reconnects on its own.
- **Battery and bandwidth**: the live socket closes when the app goes to the background and reopens with a fresh snapshot when it returns. API responses are gzipped and socket messages deflated (snapshot 260 kB → 30 kB; a minute of live updates ~7× smaller).
- **Updates**: each build stamps the service worker with a content hash. A returning visitor gets the new version in the background and a "New version is ready · Reload" card.
- **iOS limits**: Safari may clear a non-installed site's storage after about 7 days without a visit (the installed app is exempt); there is no background refresh; web push needs the app installed on iOS 16.4+.

## Before a public launch: open items

### Data terms and attribution (the biggest risk)

| Source | Used for | What to do |
|---|---|---|
| **OpenStreetMap** (tiles, `server/data/derived/routes.json`) | track geometry | ODbL. Attribution is shown on the map. `/api/routes` and `/api/shapes` publish the derived route database, so it must stay available under ODbL (it is labelled so in the response). Fine as is; keep the attribution visible. |
| **OpenFreeMap** | street base map | Free, no key. Credit it in the map attribution (the style's `openmaptiles` source currently has no explicit `attribution`; confirm OpenFreeMap's credit appears, else add it in `tiles/scripts/map-styles.mjs`). Consider a donation if traffic grows. |
| **Amtraker** (`api-v3.amtraker.com`) | Amtrak positions | Unofficial, volunteer-run. The server polls it at most every 30 s regardless of user count, but for a public app either ask its maintainer or self-host [amtraker-v3](https://github.com/piemadd/amtraker-v3) and set `AMTRAKER_URL`. |
| **MTA GTFS-RT** (LIRR, Metro-North) | live times and positions | Public, no key; follow the MTA developer terms (attribution, no implied endorsement). |
| **MTA TrainTime backend** (`backend-unified.mylirr.org`) | track numbers, consists, car loads | Undocumented app backend, not a published feed. Highest risk: could break or be blocked at any time, and its terms do not cover third-party use. Ask the MTA, or turn the equipment card off for the public version. |
| **NJ Transit** | realtime (optional) | Needs a developer-portal account; read its terms before showing it publicly. |
| **TransitDocs archive** (`asm-backend.transitdocs.com`) | Amtrak on-time history | Third-party site; ask before relying on it publicly. |
| **Railroad names and colours** | throughout | Add a "not affiliated with Amtrak, MTA or NJ Transit" line to an About screen. |

### Cost (rough; check current pricing)

- **Vercel Hobby** is free but for **non-commercial use only**; ads, sponsorships or paid features mean Pro ($20/month). The app shell is ~2 MB and cached by the service worker, so bandwidth here stays small.
- **Railway**: one 1 GB container running all month is roughly $5-10 in usage. Egress is the variable cost: an open map receives roughly 6-8 MB per hour after compression, so 100 people watching around the clock is ~15 GB/day.
- **R2**: storage for a 23 MB file is pennies; no egress fees.
- Upstream feeds are polled by the server only, so their load does not grow with users.

### Abuse and limits

- The API is read-only and every endpoint answers from memory, but there is no per-IP rate limit. Set `MAX_LIVE_CLIENTS`, and if traffic gets hostile put Cloudflare (free plan) in front of the Railway domain for rate limiting and bot protection.
- `/api/history/.../raw` and `/api/trains/.../equipment/raw` expose raw upstream records. Fine for a hobby project; consider removing them publicly given the TrainTime/TransitDocs terms above.

### Privacy and analytics

- The app sets no cookies and stores only the theme choice and the install-hint dismissal in `localStorage`. It does not use location.
- No analytics yet. Vercel Web Analytics is cookieless and needs no consent banner in most places; enable it in the Vercel project and add its script if you want visitor counts.
- Add a short privacy note (what the server logs: IP addresses in Railway's request logs).

### Branches

This web app lives in `live-map/`, from the open live-map pull request. Merge that first (or together with this change); `main` today holds only the native iOS app, which this does not touch.
