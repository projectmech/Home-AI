<script lang="ts">
  // The Home AI startup animation: the mark draws itself, a thin line fills and
  // the status text steps through the start-up stages. Ported from the owner's
  // home-ai-boot.html (same shapes, timings and wording). Calls onready when
  // the sequence ends, or at once when the system asks for reduced motion.
  import { onMount } from 'svelte';

  let { onready }: { onready?: () => void } = $props();

  let label = $state('Initializing');
  let ready = $state(false);

  onMount(() => {
    const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    if (reduced) {
      label = 'System online';
      ready = true;
      const t = setTimeout(() => onready?.(), 400);
      return () => clearTimeout(t);
    }
    const steps: [number, string][] = [
      [1800, 'Loading core'],
      [3300, 'Connecting systems'],
      [4600, 'Starting Home AI'],
      [5800, 'System online'],
    ];
    const timers = steps.map(([delay, text]) =>
      setTimeout(() => {
        label = text;
        if (delay === 5800) {
          ready = true;
          setTimeout(() => onready?.(), 700);
        }
      }, delay),
    );
    return () => timers.forEach(clearTimeout);
  });
</script>

<main class="boot" aria-label="Home AI startup animation">
  <svg class="mark" viewBox="0 0 432 432" role="img" aria-label="Home AI logo">
    <path class="shape cap" d="M107 87H327V120H107Z" />
    <path class="shape left" d="M83 142H122V267L200 327V373L83 279Z" />
    <path class="shape right" d="M313 142H352V279L235 373V327L313 267Z" />
    <path class="shape inner-left" d="M157 142H198V296L157 265Z" />
    <path class="shape inner-right" d="M237 142H278V265L237 296Z" />
  </svg>
  <div class="status" class:ready role="status">{label}</div>
  <div class="track" aria-hidden="true"><div class="progress"></div></div>
</main>

<style>
  .boot {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    place-content: center;
    justify-items: center;
    padding: 30px;
    background: #050505;
    color: #fafafa;
    font-family: system-ui, sans-serif;
  }
  .mark {
    width: min(63vw, 340px);
    animation: ignite 5.8s both;
  }
  .shape {
    fill: #fafafa;
    fill-opacity: 0;
    stroke: #fafafa;
    stroke-width: 1.1;
    stroke-linejoin: miter;
    stroke-dasharray: 1200;
    stroke-dashoffset: 1200;
    animation:
      trace 2.2s cubic-bezier(0.45, 0, 0.2, 1) forwards,
      solid 0.65s ease forwards;
    animation-delay: var(--delay), calc(var(--delay) + 1.55s);
  }
  .cap {
    --delay: 0.15s;
  }
  .left {
    --delay: 0.55s;
  }
  .right {
    --delay: 0.7s;
  }
  .inner-left {
    --delay: 1s;
  }
  .inner-right {
    --delay: 1.15s;
  }
  .status {
    height: 16px;
    margin-top: 30px;
    color: #808080;
    font:
      9px ui-monospace,
      monospace;
    letter-spacing: 3px;
    text-transform: uppercase;
    animation: appear 1s 1.5s both;
  }
  .status.ready {
    color: #d0d0d0;
  }
  .track {
    height: 1px;
    width: 140px;
    margin-top: 20px;
    background: #202020;
    overflow: hidden;
    animation: appear 1s 1s both;
  }
  .progress {
    height: 100%;
    background: #ddd;
    transform-origin: left;
    animation: load 5.5s cubic-bezier(0.2, 0.65, 0.25, 1) both;
  }
  @keyframes trace {
    to {
      stroke-dashoffset: 0;
    }
  }
  @keyframes solid {
    to {
      fill-opacity: 1;
      stroke-opacity: 0;
    }
  }
  @keyframes appear {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }
  @keyframes load {
    0% {
      transform: scaleX(0);
    }
    25% {
      transform: scaleX(0.22);
    }
    45% {
      transform: scaleX(0.28);
    }
    70% {
      transform: scaleX(0.73);
    }
    85% {
      transform: scaleX(0.79);
    }
    100% {
      transform: scaleX(1);
    }
  }
  @keyframes ignite {
    0% {
      opacity: 0;
      transform: scale(0.96);
    }
    10% {
      opacity: 1;
    }
    58% {
      filter: drop-shadow(0 0 0 transparent);
    }
    72% {
      filter: drop-shadow(0 0 13px #ffffff38);
    }
    85% {
      filter: drop-shadow(0 0 3px #ffffff18);
    }
    100% {
      opacity: 1;
      transform: scale(1);
      filter: drop-shadow(0 0 0 transparent);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .shape {
      animation: none;
      fill-opacity: 1;
      stroke-opacity: 0;
    }
    .mark,
    .status,
    .track {
      animation: none;
      opacity: 1;
    }
    .progress {
      animation: none;
      transform: scaleX(1);
    }
  }
</style>
