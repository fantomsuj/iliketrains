// Low-memory replacement for osmium's "add referenced nodes" pass.
//
// osmium tags-filter (without -R) and osmium getid allocate dense id bitmaps
// that cost ~1.6-2.8 GB regardless of output size, which gets OOM-killed on
// small machines. This streams the full extract once and keeps only the node
// ids we need (~1.3M for the US Northeast rail network, ~60 MB).
//
// Usage: node extract-way-nodes.mjs <full.osm.pbf> <ids.txt> <out.osm>
//   ids.txt: one "n<id>" per line (from the -R filtered ways)
//   out.osm: OSM XML with just those nodes (convert with osmium cat, merge)
import fs from 'node:fs';
import zlib from 'node:zlib';

const [, , pbfPath, idsPath, outPath] = process.argv;
const wanted = new Set();
for (const line of fs.readFileSync(idsPath, 'utf8').split('\n')) {
  if (line.startsWith('n')) wanted.add(Number(line.slice(1)));
}

// Minimal protobuf reader (varints decoded with float math so 64-bit ids survive).
class Reader {
  constructor(buf, pos = 0, end = buf.length) { this.buf = buf; this.pos = pos; this.end = end; }
  varint() {
    let result = 0, mul = 1, b;
    do { b = this.buf[this.pos++]; result += (b & 0x7f) * mul; mul *= 128; } while (b & 0x80);
    return result;
  }
  svarint() { const v = this.varint(); return v % 2 === 1 ? -(v + 1) / 2 : v / 2; }
  bytes() { const len = this.varint(); const s = this.pos; this.pos += len; return [s, this.pos]; }
  skip(wire) {
    if (wire === 0) this.varint();
    else if (wire === 1) this.pos += 8;
    else if (wire === 2) this.bytes();
    else if (wire === 5) this.pos += 4;
    else throw new Error('bad wire type ' + wire);
  }
  *fields() { while (this.pos < this.end) { const t = this.varint(); yield [Math.floor(t / 8), t & 7]; } }
}
function packed(buf, [s, e], signed) {
  const r = new Reader(buf, s, e), out = [];
  while (r.pos < r.end) out.push(signed ? r.svarint() : r.varint());
  return out;
}

const out = fs.openSync(outPath, 'w');
fs.writeSync(out, '<?xml version="1.0" encoding="UTF-8"?>\n<osm version="0.6" generator="extract-way-nodes">\n');
let found = 0, chunk = [];
function emit(id, lat, lon) {
  if (!wanted.has(id)) return;
  found++;
  chunk.push(`<node id="${id}" version="1" lat="${lat.toFixed(7)}" lon="${lon.toFixed(7)}"/>\n`);
  if (chunk.length > 5000) { fs.writeSync(out, chunk.join('')); chunk = []; }
}

function primitiveBlock(buf) {
  const r = new Reader(buf);
  let gran = 100, latOff = 0, lonOff = 0; const groups = [];
  for (const [f, w] of r.fields()) {
    if (f === 2 && w === 2) groups.push(r.bytes());
    else if (f === 17) gran = r.varint();
    else if (f === 19) latOff = r.varint();
    else if (f === 20) lonOff = r.varint();
    else r.skip(w);
  }
  const deg = (v, off) => (off + gran * v) * 1e-9;
  for (const g of groups) {
    const gr = new Reader(buf, g[0], g[1]);
    for (const [f, w] of gr.fields()) {
      if (f === 2 && w === 2) {
        const [s, e] = gr.bytes(); const dr = new Reader(buf, s, e);
        let ids, lats, lons;
        for (const [df, dw] of dr.fields()) {
          if (df === 1) ids = packed(buf, dr.bytes(), true);
          else if (df === 8) lats = packed(buf, dr.bytes(), true);
          else if (df === 9) lons = packed(buf, dr.bytes(), true);
          else dr.skip(dw);
        }
        let id = 0, lat = 0, lon = 0;
        for (let i = 0; i < ids.length; i++) {
          id += ids[i]; lat += lats[i]; lon += lons[i];
          emit(id, deg(lat, latOff), deg(lon, lonOff));
        }
      } else if (f === 1 && w === 2) {
        const [s, e] = gr.bytes(); const nr = new Reader(buf, s, e);
        let id = 0, lat = 0, lon = 0;
        for (const [nf, nw] of nr.fields()) {
          if (nf === 1) id = nr.svarint(); else if (nf === 8) lat = nr.svarint();
          else if (nf === 9) lon = nr.svarint(); else nr.skip(nw);
        }
        emit(id, deg(lat, latOff), deg(lon, lonOff));
      } else gr.skip(w);
    }
  }
}

const fd = fs.openSync(pbfPath, 'r');
const head = Buffer.alloc(4);
let offset = 0, blocks = 0;
for (;;) {
  if (fs.readSync(fd, head, 0, 4, offset) < 4) break;
  const hlen = head.readUInt32BE(0); offset += 4;
  const hbuf = Buffer.alloc(hlen); fs.readSync(fd, hbuf, 0, hlen, offset); offset += hlen;
  let type = '', datasize = 0;
  const hr = new Reader(hbuf);
  for (const [f, w] of hr.fields()) {
    if (f === 1) { const [s, e] = hr.bytes(); type = hbuf.toString('utf8', s, e); }
    else if (f === 3) datasize = hr.varint(); else hr.skip(w);
  }
  const bbuf = Buffer.alloc(datasize); fs.readSync(fd, bbuf, 0, datasize, offset); offset += datasize;
  if (type !== 'OSMData') continue;
  const br = new Reader(bbuf); let data = null;
  for (const [f, w] of br.fields()) {
    if (f === 1) { const [s, e] = br.bytes(); data = bbuf.subarray(s, e); }
    else if (f === 3) { const [s, e] = br.bytes(); data = zlib.inflateSync(bbuf.subarray(s, e)); }
    else br.skip(w);
  }
  if (!data) throw new Error('unsupported blob compression');
  // Nodes come first in sorted PBFs; stop once a block has no nodes and all were found.
  primitiveBlock(data);
  if (++blocks % 2000 === 0) process.stderr.write(`blocks ${blocks} found ${found}/${wanted.size}\n`);
  if (found === wanted.size) break;
}
fs.writeSync(out, chunk.join('') + '</osm>\n'); fs.closeSync(out);
process.stderr.write(`done: found ${found}/${wanted.size} nodes\n`);
