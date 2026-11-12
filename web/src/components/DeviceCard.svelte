<script lang="ts">
  import { api, ApiError, type Action, type Device, type Role } from '../lib/api';
  import { applyDevice } from '../lib/live.svelte';

  let { device, role }: { device: Device; role: Role } = $props();

  type Status = { kind: 'idle' | 'running' | 'confirmed' | 'failed' | 'denied'; text: string };
  let status = $state<Status>({ kind: 'idle', text: '' });
  let askPassword = $state(false);
  let password = $state('');

  const canControl = $derived(role !== 'restricted');
  const busy = $derived(status.kind === 'running');
  const s = $derived(device.state);

  const num = (v: unknown): number | null => (typeof v === 'number' ? v : null);

  async function run(action: Action) {
    status = { kind: 'running', text: 'Sending…' };
    try {
      const res = await api.act(device.id, action);
      applyDevice(res.device);
      status =
        res.outcome === 'confirmed'
          ? { kind: 'confirmed', text: 'Confirmed' }
          : { kind: 'failed', text: res.reason ?? 'The device did not confirm the command.' };
      askPassword = false;
    } catch (e) {
      if (e instanceof ApiError && e.code === 'step_up_required') {
        askPassword = true;
        status = { kind: 'idle', text: '' };
      } else if (e instanceof ApiError && e.status === 403) {
        status = { kind: 'denied', text: e.message };
      } else {
        status = { kind: 'failed', text: e instanceof Error ? e.message : 'Request failed.' };
      }
    } finally {
      password = '';
    }
  }

  function confirmUnlock(e: SubmitEvent) {
    e.preventDefault();
    run({ action: 'unlock', confirm_password: password });
  }

  const rangeValue = (e: Event) => Number((e.currentTarget as HTMLInputElement).value);
</script>

<article class="card">
  <div class="top">
    <h3>{device.name}</h3>
    {#if device.simulated}<span class="badge" title="Simulator device, not real hardware">Simulated</span>{/if}
  </div>

  {#if device.kind === 'light'}
    <p class="state">{s.on ? `On · ${num(s.brightness) ?? '?'}%` : 'Off'}</p>
    {#if canControl}
      <div class="row">
        <button disabled={busy} onclick={() => run({ action: 'set_power', on: !s.on })}>
          Turn {s.on ? 'off' : 'on'}
        </button>
      </div>
      <label>
        Brightness
        <input type="range" min="0" max="100" value={num(s.brightness) ?? 0} disabled={busy}
          onchange={(e) => run({ action: 'set_brightness', percent: rangeValue(e) })} />
      </label>
    {/if}
  {:else if device.kind === 'thermostat'}
    <p class="state">{num(s.current_c)?.toFixed(1) ?? 'Not available'} °C now · target {num(s.target_c)?.toFixed(1) ?? '?'} °C</p>
    {#if canControl}
      <div class="row">
        <button disabled={busy || (num(s.target_c) ?? 0) <= 5} aria-label="Lower target by half a degree"
          onclick={() => run({ action: 'set_target_temperature', celsius: (num(s.target_c) ?? 20) - 0.5 })}>−</button>
        <button disabled={busy || (num(s.target_c) ?? 0) >= 30} aria-label="Raise target by half a degree"
          onclick={() => run({ action: 'set_target_temperature', celsius: (num(s.target_c) ?? 20) + 0.5 })}>+</button>
      </div>
    {/if}
  {:else if device.kind === 'speaker'}
    <p class="state">{s.playing ? 'Playing' : 'Paused'} · volume {num(s.volume) ?? '?'}%</p>
    {#if canControl}
      <div class="row">
        <button disabled={busy} onclick={() => run({ action: 'set_playing', playing: !s.playing })}>
          {s.playing ? 'Pause' : 'Play'}
        </button>
      </div>
      <label>
        Volume
        <input type="range" min="0" max="100" value={num(s.volume) ?? 0} disabled={busy}
          onchange={(e) => run({ action: 'set_volume', percent: rangeValue(e) })} />
      </label>
    {/if}
  {:else if device.kind === 'lock'}
    <p class="state" class:warn={s.locked === false}>{s.locked ? 'Locked' : 'Unlocked'}</p>
    {#if canControl}
      {#if s.locked === false}
        <div class="row"><button disabled={busy} onclick={() => run({ action: 'lock' })}>Lock</button></div>
      {:else if askPassword}
        <form onsubmit={confirmUnlock}>
          <label>
            Enter your password to unlock
            <input type="password" bind:value={password} required autocomplete="current-password" />
          </label>
          <div class="row">
            <button class="primary" disabled={busy}>Unlock</button>
            <button type="button" onclick={() => { askPassword = false; password = ''; }}>Cancel</button>
          </div>
        </form>
      {:else}
        <div class="row"><button disabled={busy} onclick={() => run({ action: 'unlock' })}>Unlock…</button></div>
      {/if}
    {/if}
  {:else if device.kind === 'temperature_sensor'}
    <p class="state">{num(s.temperature_c)?.toFixed(1) ?? 'Not available'} °C</p>
  {:else}
    <p class="muted small">Not supported in this version.</p>
  {/if}

  <p class="status small" role="status"
    class:ok={status.kind === 'confirmed'} class:bad={status.kind === 'failed' || status.kind === 'denied'}
    class:muted={status.kind === 'running'}>
    {status.kind === 'failed' ? `Failed: ${status.text}` : status.kind === 'denied' ? `Not allowed: ${status.text}` : status.text}
  </p>
</article>

<style>
  article {
    display: grid;
    gap: 10px;
    align-content: start;
  }
  .top {
    display: flex;
    justify-content: space-between;
    align-items: start;
    gap: 8px;
  }
  .state {
    font-size: 1.1rem;
    font-weight: 500;
    font-variant-numeric: tabular-nums;
  }
  .row {
    display: flex;
    gap: 8px;
  }
  form {
    display: grid;
    gap: 10px;
  }
  .status {
    min-height: 1.2em;
  }
</style>
