<script lang="ts">
  import { onMount } from 'svelte';
  import { api, ApiError, type User } from './lib/api';
  import { connect, disconnect, live } from './lib/live.svelte';
  import Auth from './pages/Auth.svelte';
  import Home from './pages/Home.svelte';
  import Server from './pages/Server.svelte';
  import Activity from './pages/Activity.svelte';
  import Wizard from './pages/Wizard.svelte';
  import { loadPrefs } from './lib/prefs.svelte';

  type Phase = 'loading' | 'unreachable' | 'setup' | 'login' | 'app';

  let phase = $state<Phase>('loading');
  let user = $state<User | null>(null);
  let path = $state(location.pathname);

  const pages = $derived(
    user?.role === 'admin'
      ? [
          { href: '/', label: 'Home' },
          { href: '/server', label: 'Server' },
          { href: '/activity', label: 'Activity' },
        ]
      : [{ href: '/', label: 'Home' }],
  );

  async function boot() {
    try {
      const health = await api.health();
      if (health.setup_required) {
        phase = 'setup';
        return;
      }
      try {
        user = await api.me();
        enter();
      } catch (e) {
        if (e instanceof ApiError && e.status === 401) phase = 'login';
        else throw e;
      }
    } catch {
      phase = 'unreachable';
    }
  }

  function goLive() {
    connect(() => {
      user = null;
      phase = 'login';
    });
    loadPrefs();
  }

  function enter() {
    phase = 'app';
    goLive();
  }

  // The wizard created the administrator and signed them in; it keeps going.
  function adminCreated(u: User) {
    user = u;
    goLive();
  }

  function wizardDone() {
    if (user) user.setup_complete = true;
    phase = 'app';
    go('/');
  }

  const inWizard = $derived(
    phase === 'setup' || (phase === 'app' && user?.role === 'admin' && user.setup_complete === false),
  );

  function signedIn(u: User) {
    user = u;
    go('/');
    enter();
  }

  async function signOut() {
    disconnect();
    try {
      await api.logout();
    } catch {
      // The session is cleared locally either way.
    }
    user = null;
    phase = 'login';
  }

  function go(to: string) {
    if (to !== location.pathname) history.pushState({}, '', to);
    path = to;
  }

  function nav(e: MouseEvent, to: string) {
    e.preventDefault();
    go(to);
  }

  onMount(() => {
    boot();
    const onPop = () => (path = location.pathname);
    window.addEventListener('popstate', onPop);
    return () => window.removeEventListener('popstate', onPop);
  });
</script>

{#if phase === 'loading'}
  <main class="center"><p class="muted">Loading…</p></main>
{:else if phase === 'unreachable'}
  <main class="center">
    <div class="card narrow">
      <h1>Server unreachable</h1>
      <p class="muted">The Home AI server did not answer.</p>
      <button class="primary" onclick={boot}>Try again</button>
    </div>
  </main>
{:else if inWizard}
  <Wizard resume={phase === 'app'} onadmin={adminCreated} ondone={wizardDone} />
{:else if phase === 'login'}
  <Auth mode="login" onsetup={() => {}} onlogin={signedIn} />
{:else if user}
  <header>
    <strong>Home AI</strong>
    <nav aria-label="Main">
      {#each pages as p (p.href)}
        <a href={p.href} class:active={path === p.href} aria-current={path === p.href ? 'page' : undefined} onclick={(e) => nav(e, p.href)}>{p.label}</a>
      {/each}
    </nav>
    <div class="who">
      <span class="small" class:ok={live.connected} class:warn={!live.connected} role="status">
        {live.connected ? 'Live' : 'Reconnecting…'}
      </span>
      <span class="small muted">{user.username}</span>
      <button onclick={signOut}>Sign out</button>
    </div>
  </header>
  <main>
    {#if path === '/server' && user.role === 'admin'}
      <Server />
    {:else if path === '/activity' && user.role === 'admin'}
      <Activity />
    {:else}
      <Home {user} />
    {/if}
  </main>
{/if}

<style>
  header {
    position: sticky;
    top: 0;
    z-index: 5;
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px 20px;
    padding: 12px 20px;
    background: var(--surface);
    border-bottom: 1px solid var(--border);
    backdrop-filter: blur(18px) saturate(1.4);
    -webkit-backdrop-filter: blur(18px) saturate(1.4);
  }
  nav {
    display: flex;
    gap: 4px;
    flex: 1;
  }
  nav a {
    color: var(--muted);
    text-decoration: none;
    padding: 6px 12px;
    border-radius: 999px;
  }
  nav a.active {
    color: var(--text);
    background: var(--track);
  }
  .who {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  main {
    max-width: 1100px;
    margin: 0 auto;
    padding: 24px 20px 64px;
  }
  .center {
    min-height: 100vh;
    display: grid;
    place-items: center;
  }
  .narrow {
    display: grid;
    gap: 12px;
    max-width: 360px;
  }
</style>
