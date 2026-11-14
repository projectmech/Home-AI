<script lang="ts">
  // The always-on display for the Mac mini's own screen: the startup animation
  // once, then the orb full screen with a quiet status line. Open /screen in
  // the kiosk browser. It needs a signed-in session like any dashboard page.
  import { onMount } from 'svelte';
  import BootSequence from '../components/BootSequence.svelte';
  import Orb from '../components/Orb.svelte';
  import type { OrbMood } from '../lib/orb';
  import { live } from '../lib/live.svelte';

  let booted = $state(false);
  let now = $state(new Date());
  let side = $state(Math.min(innerWidth, innerHeight));

  onMount(() => {
    const tick = setInterval(() => (now = new Date()), 1000);
    const resize = () => (side = Math.min(innerWidth, innerHeight));
    addEventListener('resize', resize);
    return () => {
      clearInterval(tick);
      removeEventListener('resize', resize);
    };
  });

  // Voice states will drive this once audio clients report them; for now the
  // orb rests, and turns red if the server cannot be reached.
  const mood = $derived<OrbMood>(live.connected ? 'idle' : 'error');
  const lightsOn = $derived(live.devices.filter((d) => d.kind === 'light' && d.state.on === true).length);
  const unlocked = $derived(live.devices.filter((d) => d.kind === 'lock' && d.state.locked === false).length);
  const time = $derived(now.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }));
</script>

{#if !booted}
  <BootSequence onready={() => (booted = true)} />
{/if}

<div class="screen">
  <Orb {mood} size={Math.round(side * 0.78)} />
  <div class="status" aria-live="polite">
    <span class="time">{time}</span>
    <span>{live.connected ? 'Online' : 'Reconnecting…'}</span>
    <span>{lightsOn} {lightsOn === 1 ? 'light' : 'lights'} on</span>
    <span class:warn={unlocked > 0}>{unlocked === 0 ? 'Doors locked' : `${unlocked} unlocked`}</span>
  </div>
</div>

<style>
  .screen {
    position: fixed;
    inset: 0;
    display: grid;
    grid-template-rows: 1fr auto;
    place-items: center;
    background: #050505;
    color: #9aa;
    overflow: hidden;
  }
  .status {
    display: flex;
    gap: 28px;
    padding: 0 0 4vh;
    font:
      12px ui-monospace,
      monospace;
    letter-spacing: 3px;
    text-transform: uppercase;
  }
  .time {
    color: #d8d8d8;
  }
  .warn {
    color: #ff8a8a;
  }
</style>
