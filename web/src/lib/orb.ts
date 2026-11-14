// The JARVIS orb: a rotating 3D sphere of particles joined by faint filaments,
// with thin tilted rings around it.
//
// Look and motion are based on the standalone "jarvis-orb" the owner supplied
// (a dark blue particle-and-filament sphere). It is adapted for this
// dashboard and for the 2010 Core 2 Duo kiosk screen: filaments and particles
// are batched into a few draw calls instead of thousands, the canvas size is
// capped, and the particle count drops by itself if frames take too long.
//
// Moods: idle (slow turn), listening (reacts to the level), thinking (spins
// faster), speaking (surface ripples and level), error (red).

export type OrbMood = 'idle' | 'listening' | 'thinking' | 'speaking' | 'error';

export interface OrbInput {
  mood: OrbMood;
  /** Audio level 0..1 while listening or speaking. 0 means "no measurement": a gentle synthetic pulse is used. */
  level: number;
}

type Rgb = [number, number, number];

interface Look {
  edge: Rgb;
  ring: Rgb;
  dot: Rgb;
  spark: Rgb;
  glow: Rgb;
  /** Rotation speed, radians per second. */
  spin: number;
}

const LOOKS: Record<OrbMood, Look> = {
  idle: { edge: [74, 169, 218], ring: [57, 147, 199], dot: [93, 185, 255], spark: [170, 224, 255], glow: [12, 65, 100], spin: 0.105 },
  listening: { edge: [84, 205, 220], ring: [60, 185, 200], dot: [110, 230, 235], spark: [190, 255, 245], glow: [12, 90, 100], spin: 0.16 },
  thinking: { edge: [120, 150, 235], ring: [100, 120, 215], dot: [150, 175, 255], spark: [205, 215, 255], glow: [30, 40, 110], spin: 0.52 },
  speaking: { edge: [90, 190, 235], ring: [70, 165, 215], dot: [120, 205, 255], spark: [205, 240, 255], glow: [15, 80, 120], spin: 0.2 },
  error: { edge: [218, 90, 90], ring: [199, 70, 70], dot: [255, 140, 140], spark: [255, 200, 200], glow: [100, 25, 25], spin: 0.06 },
};

const GOLDEN = Math.PI * (3 - Math.sqrt(5));
const MAX_SIDE = 720;
const MIN_SIDE = 160;
const MIN_PARTICLES = 240;
const ALPHA_BUCKETS = 6;
const RINGS = 6;
const FRAME_MS = 1000 / 30;

const lerp = (a: number, b: number, k: number) => a + (b - a) * k;
const lerpRgb = (a: Rgb, b: Rgb, k: number): Rgb => [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)];
const rgb = (c: Rgb) => `${Math.round(c[0])},${Math.round(c[1])},${Math.round(c[2])}`;

/** A pseudo speech envelope for when no real audio level is available. */
function syntheticLevel(t: number): number {
  const v = 0.5 + 0.5 * Math.sin(t * 7.3) * Math.sin(t * 2.1 + 1) + 0.25 * Math.sin(t * 13.7);
  return Math.max(0, Math.min(1, v * 0.8));
}

interface Field {
  x: Float32Array;
  y: Float32Array;
  z: Float32Array;
  seed: Float32Array;
  size: Float32Array;
  /** Pairs of neighbouring particle indices (a, b), flattened. */
  edges: Uint16Array;
}

function makeField(count: number): Field {
  let s = 77; // fixed seed: the same orb every time
  const random = () => {
    s = (s * 16807) % 2147483647;
    return (s - 1) / 2147483646;
  };
  const x = new Float32Array(count);
  const y = new Float32Array(count);
  const z = new Float32Array(count);
  const seed = new Float32Array(count);
  const size = new Float32Array(count);
  for (let i = 0; i < count; i++) {
    const yy = 1 - (2 * (i + 0.5)) / count;
    const a = i * GOLDEN;
    const r = Math.sqrt(1 - yy * yy);
    x[i] = Math.cos(a) * r;
    y[i] = yy;
    z[i] = Math.sin(a) * r;
    seed[i] = random() * Math.PI * 2;
    size[i] = 0.45 + random();
  }
  // Neighbour distance scales so the filament density stays similar at any count.
  const reach = 0.155 * Math.sqrt(1050 / count);
  const pairs: number[] = [];
  for (let i = 0; i < count; i++) {
    for (let j = i + 1; j < count; j++) {
      if (Math.abs(y[i] - y[j]) > reach) continue;
      if (Math.hypot(x[i] - x[j], y[i] - y[j], z[i] - z[j]) < reach && random() > 0.25) pairs.push(i, j);
    }
  }
  return { x, y, z, seed, size, edges: Uint16Array.from(pairs) };
}

/**
 * Start drawing the orb into `canvas`. `read` is called every frame for the
 * current mood and level. Returns a function that stops it.
 */
export function startOrb(
  canvas: HTMLCanvasElement,
  read: () => OrbInput,
  /** Optional: told how many milliseconds each frame took to draw and how many particles it had. */
  onFrame?: (drawMs: number, particles: number) => void,
): () => void {
  const ctx = canvas.getContext('2d');
  if (!ctx) return () => {};
  const g: CanvasRenderingContext2D = ctx;

  const reduced = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  const frameMs = reduced ? 1000 / 8 : FRAME_MS;
  const timeScale = reduced ? 0.25 : 1;
  const cores = typeof navigator !== 'undefined' ? navigator.hardwareConcurrency || 2 : 2;

  let count = cores <= 2 ? 520 : 1050;
  let field = makeField(count);
  let size = 256;

  function resize() {
    const css = Math.max(canvas.clientWidth, canvas.clientHeight, 1);
    const dpr = Math.min(typeof devicePixelRatio === 'number' ? devicePixelRatio : 1, 2);
    size = Math.max(MIN_SIDE, Math.min(MAX_SIDE, Math.round(css * dpr)));
    if (canvas.width !== size || canvas.height !== size) {
      canvas.width = size;
      canvas.height = size;
    }
  }
  resize();
  const observer = typeof ResizeObserver === 'function' ? new ResizeObserver(resize) : null;
  observer?.observe(canvas);

  let edge: Rgb = [...LOOKS.idle.edge];
  let ring: Rgb = [...LOOKS.idle.ring];
  let dot: Rgb = [...LOOKS.idle.dot];
  let spark: Rgb = [...LOOKS.idle.spark];
  let glow: Rgb = [...LOOKS.idle.glow];
  let spin = LOOKS.idle.spin;
  let energy = 0;
  let rotation = 0;
  let clock = 0;
  let last = 0;
  let raf = 0;
  let stopped = false;
  let slow = 0; // consecutive slow frames
  let work = 0; // smoothed milliseconds spent drawing one frame

  // Reused every frame so drawing does not allocate.
  const px = new Float32Array(MIN_PARTICLES);
  let screenX = px;
  let screenY = px;
  let depth = px;
  let alphaOf = px;
  function ensureBuffers() {
    if (screenX.length !== count) {
      screenX = new Float32Array(count);
      screenY = new Float32Array(count);
      depth = new Float32Array(count);
      alphaOf = new Float32Array(count);
    }
  }
  ensureBuffers();

  function draw(dt: number) {
    const input = read();
    const look = LOOKS[input.mood] ?? LOOKS.idle;
    const k = Math.min(1, dt * 4);
    edge = lerpRgb(edge, look.edge, k);
    ring = lerpRgb(ring, look.ring, k);
    dot = lerpRgb(dot, look.dot, k);
    spark = lerpRgb(spark, look.spark, k);
    glow = lerpRgb(glow, look.glow, k);
    spin = lerp(spin, look.spin, k);

    clock += dt * timeScale;
    rotation += dt * spin * timeScale;
    const wantsLevel = input.mood === 'speaking' || input.mood === 'listening';
    const target = wantsLevel ? (input.level > 0 ? input.level : syntheticLevel(clock)) : 0;
    energy = lerp(energy, target, Math.min(1, dt * 12));

    const w = size;
    const h = size;
    const cy = h * 0.5;
    const radius = Math.min(w * 0.32, h * 0.405) * (1 + energy * 0.12);
    const bass = energy * 0.6;
    const treble = energy * 0.5;
    const speaking = input.mood === 'speaking';

    g.globalCompositeOperation = 'source-over';
    g.clearRect(0, 0, w, h);
    const halo = g.createRadialGradient(w / 2, cy, 0, w / 2, cy, radius * 1.45);
    halo.addColorStop(0, `rgba(${rgb(glow)},0.16)`);
    halo.addColorStop(0.65, `rgba(${rgb(glow)},0.08)`);
    halo.addColorStop(1, `rgba(${rgb(glow)},0)`);
    g.fillStyle = halo;
    g.fillRect(0, 0, w, h);

    const sin = Math.sin(rotation);
    const cos = Math.cos(rotation);
    const tilt = 0.23;
    const st = Math.sin(tilt);
    const ct = Math.cos(tilt);

    // Project every particle (perspective, with a surface ripple).
    for (let i = 0; i < count; i++) {
      const ripple =
        Math.sin(field.y[i] * 9 + clock * 1.4 + field.seed[i] * 0.25) * 0.014 +
        energy * 0.075 * Math.sin(field.y[i] * 12 + clock * 6 + field.seed[i]) +
        (speaking ? 0.025 * Math.sin(clock * 10 + field.y[i] * 8) : 0);
      const r = 1 + ripple;
      const x = (field.x[i] * cos - field.z[i] * sin) * r;
      const z = (field.x[i] * sin + field.z[i] * cos) * r;
      const y = field.y[i] * r;
      const yy = y * ct - z * st;
      const zz = y * st + z * ct;
      const scale = 3.8 / (3.8 - zz);
      screenX[i] = w / 2 + x * radius * scale;
      screenY[i] = cy + yy * radius * scale;
      depth[i] = zz;
      alphaOf[i] = 0.17 + (zz + 1) * 0.35;
    }

    g.globalCompositeOperation = 'lighter';

    // Filaments: one path per brightness bucket instead of one per line.
    const paths: Path2D[] = Array.from({ length: ALPHA_BUCKETS }, () => new Path2D());
    const boost = 1 + energy * 1.4;
    const e = field.edges;
    for (let n = 0; n < e.length; n += 2) {
      const a = e[n];
      const b = e[n + 1];
      const alpha = (0.045 + (alphaOf[a] + alphaOf[b]) * 0.085) * boost;
      const bucket = Math.min(ALPHA_BUCKETS - 1, Math.max(0, Math.floor(alpha * 10)));
      paths[bucket].moveTo(screenX[a], screenY[a]);
      paths[bucket].lineTo(screenX[b], screenY[b]);
    }
    const unit = w / 700;
    g.lineWidth = Math.max(0.6, (0.45 + bass * 0.5) * unit * 1.4);
    for (let bkt = 0; bkt < ALPHA_BUCKETS; bkt++) {
      g.strokeStyle = `rgba(${rgb(edge)},${(bkt + 0.5) / 10})`;
      g.stroke(paths[bkt]);
    }

    // Rings.
    const segments = count < 700 ? 90 : 180;
    g.lineWidth = Math.max(0.6, 0.6 * unit * 1.4);
    g.strokeStyle = `rgba(${rgb(ring)},${0.07 + energy * 0.08})`;
    g.beginPath();
    for (let rg = 0; rg < RINGS; rg++) {
      for (let s = 0; s <= segments; s++) {
        const v = (s / segments) * Math.PI * 2;
        const rr = 1 + 0.025 * Math.sin(v * 7 + clock * 0.7 + rg);
        const x = Math.cos(v) * Math.sin(rg * 0.43 + 0.35) * rr;
        const y = Math.sin(v) * rr;
        const z = Math.cos(v) * Math.cos(rg * 0.43 + 0.35) * rr;
        const xx = x * cos - z * sin;
        const zz = x * sin + z * cos;
        const yy = y * ct - zz * st;
        const d = y * st + zz * ct;
        const sc = 3.8 / (3.8 - d);
        const sx = w / 2 + xx * radius * sc;
        const sy = cy + yy * radius * sc;
        if (s === 0) g.moveTo(sx, sy);
        else g.lineTo(sx, sy);
      }
    }
    g.stroke();

    // Particles: small squares in a few brightness buckets, plus rare sparks.
    const dotBuckets = 5;
    for (let bkt = 0; bkt < dotBuckets; bkt++) {
      const lo = bkt / dotBuckets;
      const hi = (bkt + 1) / dotBuckets;
      g.fillStyle = `rgba(${rgb(dot)},${Math.min(1, lo + 0.1 + treble * 0.15)})`;
      g.beginPath();
      for (let i = 0; i < count; i++) {
        const a = Math.min(0.999, Math.max(0, alphaOf[i] / 0.87));
        if (a < lo || a >= hi) continue;
        const sz = field.size[i] * (0.45 + (depth[i] + 1) * 0.35) * (1 + energy * 0.6) * unit * 1.6;
        g.rect(screenX[i] - sz, screenY[i] - sz, sz * 2, sz * 2);
      }
      g.fill();
    }
    g.fillStyle = `rgba(${rgb(spark)},0.95)`;
    g.beginPath();
    for (let i = 0; i < count; i++) {
      if (Math.sin(clock * 1.7 + field.seed[i] * 9) <= 0.98) continue;
      const sz = 1.4 * unit * 1.6;
      g.rect(screenX[i] - sz, screenY[i] - sz, sz * 2, sz * 2);
    }
    g.fill();
    g.globalCompositeOperation = 'source-over';
  }

  function frame(now: number) {
    if (stopped) return;
    raf = requestAnimationFrame(frame);
    if (last === 0) last = now;
    const elapsed = now - last;
    if (elapsed < frameMs) return;
    last = now;
    const t0 = performance.now();
    draw(Math.min(0.1, elapsed / 1000));
    const took = performance.now() - t0;
    onFrame?.(took, count);
    work = lerp(work, took, 0.1);
    // If drawing alone eats most of the frame budget, use fewer particles.
    if (work > frameMs * 0.75 && count > MIN_PARTICLES) {
      slow++;
      if (slow >= 30) {
        count = Math.max(MIN_PARTICLES, Math.floor(count * 0.7));
        field = makeField(count);
        ensureBuffers();
        slow = 0;
        work = 0;
      }
    } else {
      slow = 0;
    }
  }
  raf = requestAnimationFrame(frame);

  return () => {
    stopped = true;
    cancelAnimationFrame(raf);
    observer?.disconnect();
  };
}
