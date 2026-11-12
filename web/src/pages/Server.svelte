<script lang="ts">
  import { onMount } from 'svelte';
  import { api, ApiError, bytes, duration, type Hardware } from '../lib/api';
  import { live } from '../lib/live.svelte';

  let hardware = $state<Hardware | null>(null);
  let error = $state('');
  let loadingHw = $state(false);

  const m = $derived(live.metrics);
  const memPct = $derived(m && m.mem_total_bytes > 0 ? (m.mem_used_bytes / m.mem_total_bytes) * 100 : 0);
  const pct = (v: number) => `${Math.max(0, Math.min(100, v)).toFixed(0)}%`;

  async function loadHardware() {
    loadingHw = true;
    error = '';
    try {
      hardware = (await api.hardware()).hardware;
    } catch (e) {
      error = e instanceof ApiError ? e.message : 'Could not load the hardware report.';
    } finally {
      loadingHw = false;
    }
  }

  onMount(async () => {
    // One immediate sample; after that the WebSocket pushes one every 10 s.
    try {
      live.metrics = (await api.metrics()).metrics;
    } catch (e) {
      error = e instanceof ApiError ? e.message : 'Could not load metrics.';
    }
    loadHardware();
  });

  const diskKind = (k: string) => (k === 'ssd' ? 'SSD' : k === 'hdd' ? 'HDD' : 'Unknown');
  const rotational = (r: boolean | null) => (r === null ? 'Unknown' : r ? 'HDD (rotational)' : 'SSD (non-rotational)');
</script>

<section>
  <h1>Server</h1>
  <p class="muted small">
    Measured on the machine running the Home AI server{m?.host_name ? ` (${m.host_name})` : ''}. Updates every 10 seconds while this page is open.
  </p>
  {#if error}<p class="bad small" role="alert">{error}</p>{/if}
</section>

{#if m}
  <section class="grid">
    <div class="card stat">
      <p class="muted small">CPU</p>
      {#if m.cpu_usage_percent === null}
        <p class="big">Measuring…</p>
      {:else}
        <p class="big">{m.cpu_usage_percent.toFixed(0)}%</p>
        <div class="bar"><span style:width={pct(m.cpu_usage_percent)}></span></div>
      {/if}
      {#if m.per_core_percent}
        <p class="muted small">Per core: {m.per_core_percent.map((c) => `${c.toFixed(0)}%`).join(' · ')}</p>
      {/if}
      <p class="muted small">Load average: {m.load_average ? m.load_average.map((l) => l.toFixed(2)).join(' / ') : 'Not available on this OS'}</p>
    </div>
    <div class="card stat">
      <p class="muted small">Memory</p>
      <p class="big">{bytes(m.mem_used_bytes)} <span class="muted of">of {bytes(m.mem_total_bytes)}</span></p>
      <div class="bar"><span style:width={pct(memPct)}></span></div>
      <p class="muted small">Swap: {m.swap_total_bytes > 0 ? `${bytes(m.swap_used_bytes)} of ${bytes(m.swap_total_bytes)}` : 'None'}</p>
      <p class="muted small">Home AI process: {bytes(m.process_rss_bytes)}</p>
    </div>
    <div class="card stat">
      <p class="muted small">System</p>
      <p class="big">Up {duration(m.uptime_s)}</p>
      <p class="muted small">{m.cpu_model || 'CPU model not reported'}</p>
      <p class="muted small">{m.logical_cores} logical / {m.physical_cores ?? 'unknown'} physical cores</p>
      <p class="muted small">{[m.os_name, m.os_version].filter(Boolean).join(' ') || 'OS not reported'} · Home AI {m.app_version}</p>
    </div>
  </section>

  <section>
    <h2>Storage</h2>
    <div class="card table-wrap">
      <table>
        <thead><tr><th>Mount</th><th>Type</th><th>File system</th><th>Free</th><th>Size</th></tr></thead>
        <tbody>
          {#each m.disks as d (d.mount + d.name)}
            <tr><td>{d.mount}</td><td>{diskKind(d.kind)}</td><td>{d.file_system}</td><td>{bytes(d.available_bytes)}</td><td>{bytes(d.total_bytes)}</td></tr>
          {:else}
            <tr><td colspan="5" class="muted">No disks reported.</td></tr>
          {/each}
        </tbody>
      </table>
    </div>
  </section>
{:else if !error}
  <p class="muted">Loading metrics…</p>
{/if}

<section>
  <div class="row">
    <h2>Hardware report</h2>
    <button onclick={loadHardware} disabled={loadingHw}>{loadingHw ? 'Running…' : 'Run again'}</button>
  </div>
  {#if hardware}
    <div class="card report">
      <p class="muted small">{hardware.note}</p>
      <dl>
        <dt>CPU</dt><dd>{hardware.cpu.model ?? 'Unknown'}</dd>
        <dt>Architecture</dt><dd>{hardware.arch}</dd>
        <dt>Boot mode</dt><dd>{hardware.boot_mode === 'unknown' ? 'Unknown' : hardware.boot_mode.toUpperCase()}</dd>
        <dt>Binary requires</dt><dd>{hardware.binary_baseline}</dd>
        <dt>CPU flags detected</dt><dd>{hardware.cpu.flags.length ? hardware.cpu.flags.join(' ') : 'Unknown'}</dd>
        <dt>Drives</dt>
        <dd>
          {#each hardware.block_devices as b (b.name)}
            <div>{b.name}: {b.model ?? 'model unknown'}, {bytes(b.size_bytes)}, {rotational(b.rotational)}</div>
          {:else}
            Unknown (drive detection needs Linux)
          {/each}
        </dd>
        <dt>SMART</dt><dd>{hardware.smart}</dd>
        <dt>Network</dt>
        <dd>
          {#each hardware.network as n (n.name)}
            <div>{n.name}: {n.addresses.join(', ') || 'no address'}</div>
          {:else}
            None reported
          {/each}
        </dd>
      </dl>
      {#each hardware.warnings as w (w)}
        <p class="warn small">{w}</p>
      {/each}
    </div>
  {/if}
</section>

<style>
  section {
    display: grid;
    gap: 12px;
    margin-bottom: 28px;
  }
  .stat {
    display: grid;
    gap: 8px;
    align-content: start;
  }
  .big {
    font-size: 1.5rem;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
  .of {
    font-size: 0.9rem;
    font-weight: 400;
  }
  .row {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .report {
    display: grid;
    gap: 12px;
  }
  dl {
    display: grid;
    grid-template-columns: minmax(110px, max-content) 1fr;
    gap: 6px 16px;
    margin: 0;
    font-size: 0.88rem;
  }
  dt {
    color: var(--muted);
  }
  dd {
    margin: 0;
    overflow-wrap: anywhere;
  }
</style>
