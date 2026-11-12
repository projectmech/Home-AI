<script lang="ts">
  import { onMount } from 'svelte';
  import { api, ApiError, type AuditEntry } from '../lib/api';

  let entries = $state<AuditEntry[]>([]);
  let error = $state('');
  let loading = $state(true);

  async function load() {
    loading = true;
    error = '';
    try {
      entries = (await api.audit()).entries;
    } catch (e) {
      error = e instanceof ApiError ? e.message : 'Could not load the activity log.';
    } finally {
      loading = false;
    }
  }

  onMount(load);

  const when = (ts: number) => new Date(ts * 1000).toLocaleString();
</script>

<section>
  <div class="row">
    <h1>Activity</h1>
    <button onclick={load} disabled={loading}>{loading ? 'Loading…' : 'Refresh'}</button>
  </div>
  <p class="muted small">Sign-ins and device commands, newest first (latest 200).</p>
  {#if error}<p class="bad small" role="alert">{error}</p>{/if}

  <div class="card table-wrap">
    <table>
      <thead><tr><th>Time</th><th>User</th><th>Action</th><th>Target</th><th>Outcome</th><th>Detail</th></tr></thead>
      <tbody>
        {#each entries as e (e.id)}
          <tr>
            <td>{when(e.ts)}</td>
            <td>{e.username ?? '—'}</td>
            <td>{e.action}</td>
            <td>{e.target ?? '—'}</td>
            <td class:ok={e.outcome === 'ok' || e.outcome === 'confirmed'} class:bad={e.outcome === 'denied' || e.outcome === 'failed'}>{e.outcome}</td>
            <td>{e.detail ?? ''}</td>
          </tr>
        {:else}
          <tr><td colspan="6" class="muted">{loading ? 'Loading…' : 'Nothing recorded yet.'}</td></tr>
        {/each}
      </tbody>
    </table>
  </div>
</section>

<style>
  section {
    display: grid;
    gap: 12px;
  }
  .row {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
</style>
