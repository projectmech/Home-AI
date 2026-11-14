<script lang="ts">
  import { startOrb, type OrbMood } from '../lib/orb';

  let {
    mood = 'idle',
    level = 0,
    size = 280,
  }: { mood?: OrbMood; level?: number; size?: number } = $props();

  let canvas: HTMLCanvasElement | undefined = $state();

  const labels: Record<OrbMood, string> = {
    idle: 'Jarvis is idle',
    listening: 'Jarvis is listening',
    thinking: 'Jarvis is thinking',
    speaking: 'Jarvis is speaking',
    error: 'Jarvis hit a problem',
  };

  // The loop reads mood and level lazily each frame, so changing them does not
  // restart the animation.
  $effect(() => {
    if (!canvas) return;
    return startOrb(canvas, () => ({ mood, level }));
  });
</script>

<div class="orb" style:width="{size}px" role="img" aria-label={labels[mood]}>
  <canvas bind:this={canvas} width="256" height="256" aria-hidden="true"></canvas>
</div>

<style>
  .orb {
    max-width: 100%;
    aspect-ratio: 1;
    margin-inline: auto;
  }
  canvas {
    display: block;
    width: 100%;
    height: 100%;
  }
</style>
