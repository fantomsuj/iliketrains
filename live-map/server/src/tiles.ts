// Serves z/x/y vector tiles out of the PMTiles archive. Production clients read the archive
// straight from a CDN (pmtiles://); this endpoint is a fallback for clients without PMTiles support.
import { existsSync } from 'node:fs';
import fs from 'node:fs/promises';
import { PMTiles, type Source, type RangeResponse } from 'pmtiles';

class FileSource implements Source {
  private handle: Promise<fs.FileHandle>;
  private path: string;
  constructor(path: string) { this.path = path; this.handle = fs.open(path, 'r'); }
  getKey() { return this.path; }
  async getBytes(offset: number, length: number): Promise<RangeResponse> {
    const buf = Buffer.alloc(length);
    const { bytesRead } = await (await this.handle).read(buf, 0, length, offset);
    return { data: buf.buffer.slice(buf.byteOffset, buf.byteOffset + bytesRead) as ArrayBuffer };
  }
}

export class TileServer {
  private pm: PMTiles | null;
  /** In production the archive usually lives on a CDN (TILES_URL) and is not on this machine: then every tile is empty. */
  constructor(file: string) { this.pm = existsSync(file) ? new PMTiles(new FileSource(file)) : null; }
  /** Uncompressed MVT bytes, or null for an empty tile. */
  async tile(z: number, x: number, y: number): Promise<Uint8Array | null> {
    if (!this.pm) return null;
    const r = await this.pm.getZxy(z, x, y);
    return r ? new Uint8Array(r.data) : null;
  }
  async header() { return this.pm?.getHeader() ?? null; }
}
