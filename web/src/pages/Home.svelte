<script lang="ts">
  import type { Device, User } from '../lib/api';
  import { live } from '../lib/live.svelte';
  import DeviceCard from '../components/DeviceCard.svelte';

  let { user }: { user: User } = $props();

  const rooms = $derived.by(() => {
    const map = new Map<string, Device[]>();
    for (const d of live.devices) {
      const list = map.get(d.room) ?? [];
      list.push(d);
      map.set(d.room, list);
    }
    return [...map.entries()].sort(([a], [b]) => a.localeCompare(b));
  });

  const allSimulated = $derived(live.devices.length > 0 && live.devices.every((d) => d.simulated));
  const lightsOn = $derived(live.devices.filter((d) => d.kind === 'light' && d.state.on === true).length);
  const locks = $derived(live.devices.filter((d) => d.kind === 'lock'));
  const unlocked = $derived(locks.filter((d) => d.state.locked === false).length);
</script>

<section class="head">
  <h1>Home</h1>
  {#if allSimulated}
    <p class="notice small">
      <span class="badge">Simulated</span>
      Every device below is a simulator. No physical connector is installed yet.
    </p>
  {/if}
</section>

{#if live.devices.length === 0}
  <p class="muted">{live.connected ? 'No devices registered.' : 'Waiting for the server…'}</p>
{:else}
  <section class="summary grid">
    <div class="card"><p class="muted small">Devices</p><p class="big">{live.devices.length}</p></div>
    <div class="card"><p class="muted small">Lights on</p><p class="big">{lightsOn}</p></div>
    <div class="card">
      <p class="muted small">Locks</p>
      <p class="big" class:warn={unlocked > 0}>
        {locks.length === 0 ? 'None' : unlocked === 0 ? 'All locked' : `${unlocked} unlocked`}
      </p>
    </div>
  </section>

  {#each rooms as [room, devices] (room)}
    <section>
      <h2>{room}</h2>
      <div class="grid">
        {#each devices as device (device.id)}
          <DeviceCard {device} role={user.role} />
        {/each}
      </div>
    </section>
  {/each}
{/if}

<style>
  section {
    display: grid;
    gap: 12px;
    margin-bottom: 28px;
  }
  .head {
    gap: 8px;
  }
  .notice {
    color: var(--muted);
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }
  .summary {
    grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
  }
  .big {
    font-size: 1.5rem;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
</style>
