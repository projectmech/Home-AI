// Generates the small boot-screen images (the typed-character dot and the
// progress bar) for the JARVIS Plymouth theme. The five shapes of the Home AI mark are
// drawn from the owner's home-ai-boot.html. No dependencies: `node os/plymouth/gen-assets.mjs`. The PNGs are
// committed; run this only when the look changes.
import { deflateSync } from 'node:zlib';
import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const out = join(dirname(fileURLToPath(import.meta.url)), '..', 'config', 'includes.chroot', 'usr', 'share', 'plymouth', 'themes', 'jarvis');
mkdirSync(out, { recursive: true });

const crcTable = new Uint32Array(256).map((_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length, 0);
  head.write(type, 4, 'latin1');
  const tail = Buffer.alloc(4);
  tail.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])), 0);
  return Buffer.concat([head, data, tail]);
};
function png(w, h, pixel) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const nx = ((x + 0.5) / w) * 2 - 1;
      const ny = ((y + 0.5) / h) * 2 - 1;
      const [r, g, b, a] = pixel(nx, ny, w);
      const o = y * (w * 4 + 1) + 1 + x * 4;
      raw[o] = r;
      raw[o + 1] = g;
      raw[o + 2] = b;
      raw[o + 3] = Math.round(Math.max(0, Math.min(1, a)) * 255);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const clamp = (v, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);

const dot = (nx, ny) => {
  const d = Math.hypot(nx, ny);
  return [250, 250, 250, d >= 1 ? 0 : Math.pow(1 - d, 1.2)];
};

const bar = () => [221, 221, 221, 1];

// The five shapes of the Home AI mark, from the owner's home-ai-boot.html
// (viewBox 0 0 432 432). Each is its own full-size image so the boot script can
// bring them in one after another. Rasterised with 4x4 supersampling.
const SHAPES = {
  'cap.png': [[107, 87], [327, 87], [327, 120], [107, 120]],
  'left.png': [[83, 142], [122, 142], [122, 267], [200, 327], [200, 373], [83, 279]],
  'right.png': [[313, 142], [352, 142], [352, 279], [235, 373], [235, 327], [313, 267]],
  'inner-left.png': [[157, 142], [198, 142], [198, 296], [157, 265]],
  'inner-right.png': [[237, 142], [278, 142], [278, 265], [237, 296]],
};
const inside = (poly, x, y) => {
  let c = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i];
    const [xj, yj] = poly[j];
    if (yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) c = !c;
  }
  return c;
};
const shape = (poly) => (nx, ny, w) => {
  const px = ((nx + 1) / 2) * w;
  const py = ((ny + 1) / 2) * w;
  let hits = 0;
  for (let sy = 0; sy < 4; sy++) for (let sx = 0; sx < 4; sx++) if (inside(poly, px - 0.5 + (sx + 0.5) / 4, py - 0.5 + (sy + 0.5) / 4)) hits++;
  return [250, 250, 250, hits / 16];
};

const files = {
  'dot.png': png(16, 16, dot),
  'bar.png': png(4, 4, bar),
};
for (const [name, poly] of Object.entries(SHAPES)) files[name] = png(432, 432, shape(poly));
for (const [name, data] of Object.entries(files)) {
  writeFileSync(join(out, name), data);
  console.log(name, data.length, 'bytes');
}
