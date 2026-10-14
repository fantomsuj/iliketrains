// Feed transport. LiveFetcher polls HTTP (and optionally records every response);
// ReplayFetcher serves recorded responses against a virtual clock (demo mode).
import fs from 'node:fs';
import path from 'node:path';

export interface Clock { now(): number }
export const realClock: Clock = { now: () => Date.now() };

export interface FetchInit { headers?: Record<string, string>; method?: string; body?: FormData | string; maxAgeMs?: number }

export interface Fetcher {
  /** Raw body of the feed `key`, or null when unavailable. */
  get(key: string, url: string, init?: FetchInit): Promise<Buffer | null>;
}

export class LiveFetcher implements Fetcher {
  private cache = new Map<string, { at: number; body: Buffer; etag?: string }>();
  private userAgent: string; private recordDir: string; private minIntervalMs: number;
  constructor(userAgent: string, recordDir = '', minIntervalMs = 10_000) {
    this.userAgent = userAgent; this.recordDir = recordDir; this.minIntervalMs = minIntervalMs;
  }

  async get(key: string, url: string, init: FetchInit = {}): Promise<Buffer | null> {
    const cached = this.cache.get(key);
    // Never hit a feed more often than minIntervalMs no matter how many callers ask (Amtraker is volunteer-run).
    if (cached && Date.now() - cached.at < (init.maxAgeMs ?? this.minIntervalMs)) return cached.body;
    const h: Record<string, string> = { 'User-Agent': this.userAgent, ...init.headers };
    if (cached?.etag) h['If-None-Match'] = cached.etag;
    const res = await fetch(url, { headers: h, method: init.method ?? 'GET', body: init.body, signal: AbortSignal.timeout(15_000) });
    if (res.status === 304 && cached) { cached.at = Date.now(); return cached.body; }
    if (!res.ok) throw new Error(`${key}: HTTP ${res.status}`);
    const body = Buffer.from(await res.arrayBuffer());
    this.cache.set(key, { at: Date.now(), body, etag: res.headers.get('etag') ?? undefined });
    if (this.recordDir) {
      const dir = path.join(this.recordDir, key);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(path.join(dir, `${Date.now()}.bin`), body);
    }
    return body;
  }
}

/**
 * Plays back a directory recorded with TRAINS_RECORD_DIR: <dir>/<key>/<epochMs>.bin.
 * Virtual time starts at the first recording and loops when it reaches the last one.
 */
export class ReplayFetcher implements Fetcher, Clock {
  private files = new Map<string, { t: number; file: string }[]>();
  private start: number; private end: number; private wallStart = Date.now();

  constructor(dir: string) {
    for (const key of fs.readdirSync(dir)) {
      const sub = path.join(dir, key);
      if (!fs.statSync(sub).isDirectory()) continue;
      const list = fs.readdirSync(sub).filter((f) => f.endsWith('.bin'))
        .map((f) => ({ t: Number(f.replace('.bin', '')), file: path.join(sub, f) })).sort((a, b) => a.t - b.t);
      if (list.length) this.files.set(key, list);
    }
    if (!this.files.size) throw new Error(`no recordings in ${dir}`);
    const all = [...this.files.values()].flat().map((x) => x.t);
    this.start = Math.min(...all); this.end = Math.max(...all);
  }

  now(): number {
    const span = Math.max(1, this.end - this.start + 30_000);
    return this.start + ((Date.now() - this.wallStart) % span);
  }

  async get(key: string): Promise<Buffer | null> {
    const list = this.files.get(key);
    if (!list) return null;
    const t = this.now();
    let pick = list[0];
    for (const x of list) if (x.t <= t) pick = x; else break;
    return fs.readFileSync(pick.file);
  }
}
