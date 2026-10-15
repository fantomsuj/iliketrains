// Builds tiles/style/trains-light.json: a clean, light street map in the spirit of Apple Maps /
// Flighty, under the Trains rail layers.
// Base: OpenFreeMap's "liberty" style (openmaptiles schema, OSM data, free, no key), saved in
// tiles/style/openfreemap-liberty.json so the build is repeatable; recoloured here. On top: the rail
// layers of our own PMTiles (from trains-dark.json), recoloured light.
//   node tiles/scripts/light-style.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const STYLE_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '../style');
const base = JSON.parse(fs.readFileSync(path.join(STYLE_DIR, 'openfreemap-liberty.json'), 'utf8'));
const ours = JSON.parse(fs.readFileSync(path.join(STYLE_DIR, 'trains-dark.json'), 'utf8'));

const C = {
  land: '#f4f2ee', residential: '#efebe5', park: '#d5ebc5', wood: '#cfe6bd', grass: '#dcefcf', water: '#a7d4f5',
  waterLine: '#93c6ec', sand: '#f3ead2', building: '#e7e3dc', buildingEdge: '#dcd6cd', aeroway: '#e9e6e1',
  road: '#ffffff', roadCasing: '#e0dbd2', minorCasing: '#e8e4dd', major: '#fffaf0', majorCasing: '#ebe1c7',
  motorway: '#fdf0c4', motorwayCasing: '#e8d398', path: '#e2ddd5', label: '#55585e', labelSoft: '#8a8d93', halo: '#ffffff',
  boundary: '#c9c3d6',
};

// Layers we don't want: points of interest (clutter), 3D buildings, shaded relief, and the base map's
// own railways (our rail layers draw the network).
const drop = (id) => /^poi_|building-3d|natural_earth|_rail|rail_hatching|road_one_way|aerodrome|airport|road_area_pattern/.test(id);

function paintFor(l) {
  const id = l.id, p = { ...(l.paint ?? {}) };
  const set = (k, v) => { p[k] = v; };
  if (id === 'background') set('background-color', C.land);
  else if (id === 'water') set('fill-color', C.water);
  else if (id.startsWith('waterway') && l.type === 'line') set('line-color', C.waterLine);
  else if (id === 'park') { set('fill-color', C.park); set('fill-opacity', 0.9); delete p['fill-outline-color']; }
  else if (id === 'park_outline') set('line-opacity', 0);
  else if (id === 'landcover_wood') { set('fill-color', C.wood); set('fill-opacity', 0.6); }
  else if (id === 'landcover_grass' || id === 'landuse_pitch' || id === 'landuse_cemetery') { set('fill-color', C.grass); set('fill-opacity', 0.7); }
  else if (id === 'landcover_sand') set('fill-color', C.sand);
  else if (id === 'landuse_residential') set('fill-color', C.residential);
  else if (id.startsWith('landuse_')) set('fill-color', C.residential);
  else if (id === 'building') { set('fill-color', C.building); set('fill-outline-color', C.buildingEdge); }
  else if (id.startsWith('aeroway')) { if ('fill-color' in p) set('fill-color', C.aeroway); if ('line-color' in p) set('line-color', '#dedad3'); }
  else if (id.startsWith('boundary')) set('line-color', C.boundary);
  else if (l.type === 'line' && /road|tunnel|bridge/.test(id)) {
    const casing = id.endsWith('casing');
    const motorway = /motorway/.test(id), major = /trunk_primary/.test(id), path_ = /path|pedestrian/.test(id);
    set('line-color', casing ? (motorway ? C.motorwayCasing : major ? C.majorCasing : /minor|street|service/.test(id) ? C.minorCasing : C.roadCasing)
      : motorway ? C.motorway : major ? C.major : path_ ? C.path : C.road);
    if (path_ && !casing) delete p['line-dasharray'];
    if (id.startsWith('tunnel')) set('line-opacity', 0.5);
  } else if (l.type === 'symbol' && 'text-color' in p) {
    const soft = /water|highway-name|label_other|label_village/.test(id);
    set('text-color', /water/.test(id) ? '#5f8fb8' : soft ? C.labelSoft : C.label);
    set('text-halo-color', C.halo); set('text-halo-width', 1.2); delete p['text-halo-blur'];
  }
  return p;
}

const layers = base.layers.filter((l) => !drop(l.id)).map((l) => {
  const out = { ...l, paint: paintFor(l) };
  if (l.layout?.['icon-image'] && /label_city/.test(l.id)) out.layout = { ...l.layout, 'icon-image': '' }; // no city dots
  return out;
});

// our rail network, light: main lines a soft grey, branches lighter; stations as small white dots
const RAIL = { 'rail-main': '#bdb7ad', 'rail-branch': '#ccc7be', 'rail-transit': '#d3cec6', 'rail-service': '#e0dcd5' };
const above = (id) => layers.findIndex((l) => l.id === 'building') + 1;
const railLayers = ours.layers.filter((l) => l.id in RAIL).map((l) => ({ ...l, paint: { ...l.paint, 'line-color': RAIL[l.id] } }));
layers.splice(above(), 0, ...railLayers);
const st = ours.layers.filter((l) => l.id.startsWith('stations-osm')).map((l) => ({ ...l,
  paint: l.type === 'circle' ? { ...l.paint, 'circle-color': '#ffffff', 'circle-stroke-color': '#b3ada3' }
    : { ...l.paint, 'text-color': C.labelSoft, 'text-halo-color': C.halo } }));
const firstLabel = layers.findIndex((l) => l.type === 'symbol');
layers.splice(firstLabel, 0, ...st);
// the app inserts its route lines under the layer called 'places'; keep a (hidden-by-default) anchor
layers.splice(firstLabel, 0, { id: 'places', type: 'background', layout: { visibility: 'none' } });

const style = {
  version: 8, name: 'Trains light',
  metadata: { note: 'Generated by tiles/scripts/light-style.mjs from OpenFreeMap liberty + trains-dark.json' },
  sources: { openmaptiles: { type: 'vector', url: 'https://tiles.openfreemap.org/planet' }, trains: ours.sources.trains },
  sprite: base.sprite, glyphs: base.glyphs, layers,
};
fs.writeFileSync(path.join(STYLE_DIR, 'trains-light.json'), JSON.stringify(style, null, 1));
console.log(`wrote trains-light.json: ${layers.length} layers`);
