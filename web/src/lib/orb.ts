// The JARVIS orb: a glowing core, a shell of orbiting points, thin rings, and
// per-state effects (breathing, listening ripples, thinking spin, speaking
// level spokes, error red). Plain 2D canvas, no libraries, no shaders: it has
// to run on a 2010 Core 2 Duo with software rendering, so it draws at a small
// fixed internal size (the page scales it up), caps at 30 frames per second,
// and slows right down when the system asks for reduced motion.

export type OrbMood = 'idle' | 'listening' | 'thinking' | 'speaking' | 'error';

export interface OrbInput {
  mood: OrbMood;
  /** Audio level 0..1 while speaking or listening. 0 means "no measurement": a gentle synthetic pulse is used. */
  level: number;
}

type Rgb = [number, number, number];

interface Look {
  core: Rgb;
  glow: Rgb;
  /** Rotation speed of the shell, radians per second. */
  spin: number;
  /** Idle breathing amplitude, fraction of the radius. */
  breath: number;
  /** Glow strength 0..1. */
  glowAmount: number;
}

const LOOKS: Record<OrbMood, Look> = {
  idle: { core: [70, 200, 255], glow: [40, 150, 255], spin: 0.25, breath: 0.045, glowAmount: 0.5 },
  listening: { core: [90, 255, 215], glow: [40, 230, 190], spin: 0.45, breath: 0.03, glowAmount: 0.7 },
  thinking: { core: [150, 160, 255], glow: [110, 110, 255], spin: 1.9, breath: 0.02, glowAmount: 0.65 },
  speaking: { core: [190, 240, 255], glow: [70, 190, 255], spin: 0.7, breath: 0, glowAmount: 0.85 },
  error: { core: [255, 95, 95], glow: [255, 60, 60], spin: 0.12, breath: 0.06, glowAmount: 0.6 },
};

const SIZE = 256;
const POINTS = 72;
const FRAME_MS = 1000 / 30;
const GOLDEN = Math.PI * (3 - Math.sqrt(5));

// Points spread evenly over a unit sphere (Fibonacci lattice).
const SPHERE: [number, number, number][] = Array.from({ length: POINTS }, (_, i) => {
  const y = 1 - (2 * (i + 0.5)) / POINTS;
  const ring = Math.sqrt(1 - y * y);
  const a = GOLDEN * i;
  return [Math.cos(a) * ring, y, Math.sin(a) * ring];
});

const lerp = (a: number, b: number, k: number) => a + (b - a) * k;
const lerpRgb = (a: Rgb, b: Rgb, k: number): Rgb => [lerp(a[0], b[0], k), lerp(a[1], b[1], k), lerp(a[2], b[2], k)];
const rgb = (c: Rgb) => `${Math.round(c[0])},${Math.round(c[1])},${Math.round(c[2])}`;

/** A pseudo speech envelope for when no real audio level is available. */
function syntheticLevel(t: number): number {
  const v = 0.5 + 0.5 * Math.sin(t * 7.3) * Math.sin(t * 2.1 + 1) + 0.25 * Math.sin(t * 13.7);
  return Math.max(0, Math.min(1, v * 0.8));
}

/**
 * Start drawing the orb into `canvas` (any size; it is drawn at 256x256 and
 * should be given width/height attributes of 256). `read` is called every frame
 * for the current mood and level. Returns a function that stops it.
 */
export function startOrb(canvas: HTMLCanvasElement, read: () => OrbInput): () => void {
  const ctx = canvas.getContext('2d');
  if (!ctx) return () => {};
  const g: CanvasRenderingContext2D = ctx;
  canvas.width = SIZE;
  canvas.height = SIZE;

  const reduced = typeof matchMedia === 'function' && matchMedia('(prefers-reduced-motion: reduce)').matches;
  const frameMs = reduced ? 1000 / 8 : FRAME_MS;
  const timeScale = reduced ? 0.25 : 1;

  let core: Rgb = [...LOOKS.idle.core];
  let glow: Rgb = [...LOOKS.idle.glow];
  let spin = LOOKS.idle.spin;
  let breath = LOOKS.idle.breath;
  let glowAmount = LOOKS.idle.glowAmount;
  let level = 0;
  let angle = 0;
  let clock = 0;
  let last = 0;
  let raf = 0;
  let stopped = false;

  function draw(dt: number) {
    const input = read();
    const look = LOOKS[input.mood] ?? LOOKS.idle;
    const k = Math.min(1, dt * 4);
    core = lerpRgb(core, look.core, k);
    glow = lerpRgb(glow, look.glow, k);
    spin = lerp(spin, look.spin, k);
    breath = lerp(breath, look.breath, k);
    glowAmount = lerp(glowAmount, look.glowAmount, k);

    clock += dt * timeScale;
    angle += dt * spin * timeScale;
    const wantsLevel = input.mood === 'speaking' || input.mood === 'listening';
    const target = wantsLevel ? (input.level > 0 ? input.level : syntheticLevel(clock)) : 0;
    level = lerp(level, target, Math.min(1, dt * 12));

    const c = SIZE / 2;
    const base = SIZE * 0.2;
    const pulse = input.mood === 'speaking' ? level * 0.16 : input.mood === 'listening' ? level * 0.05 : 0;
    const r = base * (1 + breath * Math.sin(clock * 1.6) + pulse);
    const coreRgb = rgb(core);
    const glowRgb = rgb(glow);

    g.globalCompositeOperation = 'source-over';
    g.clearRect(0, 0, SIZE, SIZE);

    // Outer glow.
    const halo = g.createRadialGradient(c, c, r * 0.5, c, c, SIZE * 0.5);
    halo.addColorStop(0, `rgba(${glowRgb},${0.55 * glowAmount})`);
    halo.addColorStop(0.45, `rgba(${glowRgb},${0.16 * glowAmount})`);
    halo.addColorStop(1, `rgba(${glowRgb},0)`);
    g.fillStyle = halo;
    g.fillRect(0, 0, SIZE, SIZE);

    // Core sphere with an off-centre highlight.
    const body = g.createRadialGradient(c - r * 0.3, c - r * 0.35, r * 0.05, c, c, r);
    body.addColorStop(0, 'rgba(255,255,255,0.95)');
    body.addColorStop(0.3, `rgba(${coreRgb},0.95)`);
    body.addColorStop(1, `rgba(${glowRgb},0.35)`);
    g.fillStyle = body;
    g.beginPath();
    g.arc(c, c, r, 0, Math.PI * 2);
    g.fill();

    g.globalCompositeOperation = 'lighter';

    // Listening: ripples that spread outwards.
    if (input.mood === 'listening') {
      for (let i = 0; i < 3; i++) {
        const phase = (clock / 1.8 + i / 3) % 1;
        const rr = r * (1.1 + phase * 1.5);
        g.strokeStyle = `rgba(${glowRgb},${0.5 * (1 - phase)})`;
        g.lineWidth = 1.5;
        g.beginPath();
        g.arc(c, c, rr, 0, Math.PI * 2);
        g.stroke();
      }
    }

    // Rings, tilted differently and turning at different rates.
    g.lineWidth = 1;
    for (let i = 0; i < 3; i++) {
      g.strokeStyle = `rgba(${coreRgb},${0.32 - i * 0.06})`;
      if (input.mood === 'thinking') g.setLineDash([10 + i * 6, 8]);
      else g.setLineDash([]);
      g.beginPath();
      g.ellipse(c, c, r * (1.35 + i * 0.22), r * (0.45 + i * 0.12), angle * (0.8 + i * 0.5) + i * 1.1, 0, Math.PI * 2);
      g.stroke();
    }
    g.setLineDash([]);

    // Speaking: spokes around the core, as long as the voice is loud.
    if (input.mood === 'speaking') {
      const spokes = 48;
      g.strokeStyle = `rgba(${coreRgb},0.7)`;
      g.lineWidth = 1.5;
      g.beginPath();
      for (let i = 0; i < spokes; i++) {
        const a = (i / spokes) * Math.PI * 2;
        const wobble = 0.5 + 0.5 * Math.sin(clock * 9 + i * 1.7);
        const len = r * (0.08 + 0.5 * level * wobble);
        const r0 = r * 1.12;
        g.moveTo(c + Math.cos(a) * r0, c + Math.sin(a) * r0);
        g.lineTo(c + Math.cos(a) * (r0 + len), c + Math.sin(a) * (r0 + len));
      }
      g.stroke();
    }

    // Shell of orbiting points; nearer points are bigger and brighter.
    const ca = Math.cos(angle);
    const sa = Math.sin(angle);
    const tilt = 0.45;
    const ct = Math.cos(tilt);
    const st = Math.sin(tilt);
    const shell = r * 1.55;
    for (const [x, y, z] of SPHERE) {
      const x1 = x * ca + z * sa;
      const z1 = -x * sa + z * ca;
      const y1 = y * ct - z1 * st;
      const z2 = y * st + z1 * ct;
      const depth = (z2 + 1) / 2;
      g.fillStyle = `rgba(${coreRgb},${0.12 + 0.7 * depth})`;
      g.beginPath();
      g.arc(c + x1 * shell, c + y1 * shell, 0.7 + 1.5 * depth, 0, Math.PI * 2);
      g.fill();
    }
    g.globalCompositeOperation = 'source-over';
  }

  function frame(now: number) {
    if (stopped) return;
    raf = requestAnimationFrame(frame);
    if (last === 0) last = now;
    const elapsed = now - last;
    if (elapsed < frameMs) return;
    last = now;
    draw(Math.min(0.1, elapsed / 1000));
  }
  raf = requestAnimationFrame(frame);

  return () => {
    stopped = true;
    cancelAnimationFrame(raf);
  };
}
