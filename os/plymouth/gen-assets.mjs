// Generates the boot-screen images (plain RGBA PNGs) for the JARVIS Plymouth
// theme. No dependencies: `node os/plymouth/gen-assets.mjs`. The PNGs are
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

// Soft glow around the orb.
const halo = (nx, ny) => {
  const d = Math.hypot(nx, ny);
  return [60, 170, 255, d >= 1 ? 0 : Math.pow(1 - d, 2.4) * 0.9];
};

// The sphere: bright off-centre highlight fading to the edge colour.
const core = (nx, ny, w) => {
  const d = Math.hypot(nx, ny);
  const edge = clamp((1 - d) * (w / 2));
  const t = clamp(Math.hypot(nx + 0.3, ny + 0.35) / 1.1);
  const stops = [
    [0, [255, 255, 255, 0.95]],
    [0.3, [70, 200, 255, 0.95]],
    [1, [40, 150, 255, 0.35]],
  ];
  let c = stops[stops.length - 1][1];
  for (let i = 0; i < stops.length - 1; i++) {
    const [t0, c0] = stops[i];
    const [t1, c1] = stops[i + 1];
    if (t <= t1) {
      c = mix(c0, c1, clamp((t - t0) / (t1 - t0)));
      break;
    }
  }
  return [c[0], c[1], c[2], c[3] * edge];
};

// A thin tilted-ellipse ring; the script rotates it.
const ring = (nx, ny, w) => {
  const a = 0.96;
  const b = 0.34;
  const f = Math.hypot(nx / a, ny / b);
  const px = Math.abs(f - 1) * b * (w / 2);
  return [120, 215, 255, clamp(1 - px / 1.3) * 0.55];
};

const dot = (nx, ny) => {
  const d = Math.hypot(nx, ny);
  return [190, 240, 255, d >= 1 ? 0 : Math.pow(1 - d, 1.2)];
};

const bar = () => [90, 210, 255, 1];

const files = {
  'halo.png': png(512, 512, halo),
  'core.png': png(256, 256, core),
  'ring.png': png(256, 256, ring),
  'dot.png': png(16, 16, dot),
  'bar.png': png(4, 4, bar),
};
for (const [name, data] of Object.entries(files)) {
  writeFileSync(join(out, name), data);
  console.log(name, data.length, 'bytes');
}
