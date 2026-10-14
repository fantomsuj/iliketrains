// Geometry helpers shared by the offline route builder and the live server.
// Coordinates are [lon, lat] in degrees; distances are metres.

export type LonLat = [number, number];

const R = 6371008.8;
const RAD = Math.PI / 180;

export function haversine(a: LonLat, b: LonLat): number {
  const dLat = (b[1] - a[1]) * RAD;
  const dLon = (b[0] - a[0]) * RAD;
  const s = Math.sin(dLat / 2) ** 2 + Math.cos(a[1] * RAD) * Math.cos(b[1] * RAD) * Math.sin(dLon / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}

export function bearing(a: LonLat, b: LonLat): number {
  const y = Math.sin((b[0] - a[0]) * RAD) * Math.cos(b[1] * RAD);
  const x = Math.cos(a[1] * RAD) * Math.sin(b[1] * RAD) -
    Math.sin(a[1] * RAD) * Math.cos(b[1] * RAD) * Math.cos((b[0] - a[0]) * RAD);
  return (Math.atan2(y, x) / RAD + 360) % 360;
}

/** Project p onto segment a-b in a local equirectangular frame. t in [0,1], dist in metres. */
export function projectOnSegment(p: LonLat, a: LonLat, b: LonLat): { t: number; dist: number; point: LonLat } {
  const kx = Math.cos(p[1] * RAD) * RAD * R;
  const ky = RAD * R;
  const ax = (a[0] - p[0]) * kx, ay = (a[1] - p[1]) * ky;
  const bx = (b[0] - p[0]) * kx, by = (b[1] - p[1]) * ky;
  const dx = bx - ax, dy = by - ay;
  const len2 = dx * dx + dy * dy;
  let t = len2 === 0 ? 0 : -(ax * dx + ay * dy) / len2;
  t = Math.max(0, Math.min(1, t));
  const qx = ax + t * dx, qy = ay + t * dy;
  return { t, dist: Math.hypot(qx, qy), point: [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])] };
}

/** A polyline with cumulative distance, the representation every route uses. */
export class Polyline {
  readonly coords: LonLat[];
  readonly cum: Float64Array;

  constructor(coords: LonLat[]) {
    this.coords = coords;
    this.cum = new Float64Array(coords.length);
    for (let i = 1; i < coords.length; i++) this.cum[i] = this.cum[i - 1] + haversine(coords[i - 1], coords[i]);
  }

  get length(): number { return this.cum.length ? this.cum[this.cum.length - 1] : 0; }

  /** Index i such that cum[i] <= d < cum[i+1]. */
  private segmentAt(d: number): number {
    let lo = 0, hi = this.cum.length - 1;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (this.cum[mid] <= d) lo = mid; else hi = mid; }
    return lo;
  }

  pointAt(d: number): { lonlat: LonLat; bearing: number } {
    const n = this.coords.length;
    if (n === 1) return { lonlat: this.coords[0], bearing: 0 };
    d = Math.max(0, Math.min(this.length, d));
    const i = Math.min(this.segmentAt(d), n - 2);
    const a = this.coords[i], b = this.coords[i + 1];
    const segLen = this.cum[i + 1] - this.cum[i];
    const t = segLen > 0 ? (d - this.cum[i]) / segLen : 0;
    return { lonlat: [a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])], bearing: bearing(a, b) };
  }

  /**
   * Nearest point on the line to p, optionally restricted to distances in [minD, maxD].
   * Restricting matters for routes that pass the same place twice (loops, out-and-back).
   */
  project(p: LonLat, minD = 0, maxD = Infinity): { d: number; offset: number } {
    let best = { d: 0, offset: Infinity };
    const n = this.coords.length;
    if (n === 1) return { d: 0, offset: haversine(p, this.coords[0]) };
    const start = minD > 0 ? this.segmentAt(minD) : 0;
    for (let i = start; i < n - 1; i++) {
      if (this.cum[i] > maxD) break;
      const r = projectOnSegment(p, this.coords[i], this.coords[i + 1]);
      if (r.dist < best.offset) {
        const d = this.cum[i] + r.t * (this.cum[i + 1] - this.cum[i]);
        if (d >= minD && d <= maxD) best = { d, offset: r.dist };
      }
    }
    return best;
  }

  /** Sub-line between two distances. */
  slice(d0: number, d1: number): LonLat[] {
    const out: LonLat[] = [this.pointAt(d0).lonlat];
    for (let i = 0; i < this.coords.length; i++) if (this.cum[i] > d0 && this.cum[i] < d1) out.push(this.coords[i]);
    out.push(this.pointAt(d1).lonlat);
    return out;
  }
}

/** Resample a line so consecutive points are at most `step` metres apart. */
export function densify(coords: LonLat[], step: number): LonLat[] {
  const out: LonLat[] = [];
  for (let i = 0; i < coords.length; i++) {
    if (i > 0) {
      const a = coords[i - 1], b = coords[i];
      const n = Math.floor(haversine(a, b) / step);
      for (let k = 1; k <= n; k++) {
        const t = k / (n + 1);
        out.push([a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1])]);
      }
    }
    out.push(coords[i]);
  }
  return out;
}

/** Drop points closer than `minGap` metres to the previous kept point. */
export function thin(coords: LonLat[], minGap: number): LonLat[] {
  if (coords.length < 3) return coords.slice();
  const out: LonLat[] = [coords[0]];
  for (let i = 1; i < coords.length - 1; i++) if (haversine(out[out.length - 1], coords[i]) >= minGap) out.push(coords[i]);
  out.push(coords[coords.length - 1]);
  return out;
}

// Google encoded polyline, precision 1e5 (what the iOS and web clients decode).
export function encodePolyline(coords: LonLat[], precision = 1e5): string {
  let out = '', pLat = 0, pLon = 0;
  const enc = (v: number) => {
    let s = v < 0 ? ~(v << 1) : v << 1;
    while (s >= 0x20) { out += String.fromCharCode((0x20 | (s & 0x1f)) + 63); s >>= 5; }
    out += String.fromCharCode(s + 63);
  };
  for (const [lon, lat] of coords) {
    const la = Math.round(lat * precision), lo = Math.round(lon * precision);
    enc(la - pLat); enc(lo - pLon); pLat = la; pLon = lo;
  }
  return out;
}

export function decodePolyline(s: string, precision = 1e5): LonLat[] {
  const out: LonLat[] = [];
  let i = 0, lat = 0, lon = 0;
  const dec = () => {
    let r = 0, shift = 0, b;
    do { b = s.charCodeAt(i++) - 63; r |= (b & 0x1f) << shift; shift += 5; } while (b >= 0x20);
    return r & 1 ? ~(r >> 1) : r >> 1;
  };
  while (i < s.length) { lat += dec(); lon += dec(); out.push([lon / precision, lat / precision]); }
  return out;
}

/** Douglas-Peucker simplification with a tolerance in metres. */
export function simplify(coords: LonLat[], tolerance: number): LonLat[] {
  if (coords.length < 3) return coords.slice();
  const keep = new Uint8Array(coords.length);
  keep[0] = keep[coords.length - 1] = 1;
  const stack: [number, number][] = [[0, coords.length - 1]];
  while (stack.length) {
    const [a, b] = stack.pop()!;
    let maxD = 0, idx = -1;
    for (let i = a + 1; i < b; i++) {
      const d = projectOnSegment(coords[i], coords[a], coords[b]).dist;
      if (d > maxD) { maxD = d; idx = i; }
    }
    if (idx >= 0 && maxD > tolerance) { keep[idx] = 1; stack.push([a, idx], [idx, b]); }
  }
  return coords.filter((_, i) => keep[i]);
}
