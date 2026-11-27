// The service region. Matches the tile build bounds in tiles/build.sh.
import type { LonLat } from './geo/geo.ts';

export const REGION_BBOX = { west: -80.6, south: 38.6, east: -66.8, north: 47.6 };

export function inRegion([lon, lat]: LonLat): boolean {
  return lon >= REGION_BBOX.west && lon <= REGION_BBOX.east && lat >= REGION_BBOX.south && lat <= REGION_BBOX.north;
}
