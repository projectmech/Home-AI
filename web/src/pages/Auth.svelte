<script lang="ts">
  import { api, ApiError, type User } from '../lib/api';

  let {
    mode,
    onsetup,
    onlogin,
  }: { mode: 'setup' | 'login'; onsetup: () => void; onlogin: (u: User) => void } = $props();

  let token = $state('');
  let username = $state('');
  let password = $state('');
  let confirm = $state('');
  let error = $state('');
  let notice = $state('');
  let busy = $state(false);

  async function submit(e: SubmitEvent) {
    e.preventDefault();
    error = '';
    if (mode === 'setup' && password !== confirm) {
      error = 'The two passwords do not match.';
      return;
    }
    busy = true;
    try {
      if (mode === 'setup') {
        await api.setup(token, username, password);
        password = '';
        confirm = '';
        token = '';
        notice = 'Administrator created. Sign in to continue.';
        onsetup();
      } else {
        const user = await api.login(username, password);
        password = '';
        onlogin(user);
      }
    } catch (err) {
      error = err instanceof ApiError ? err.message : 'Something went wrong.';
    } finally {
      busy = false;
    }
  }
</script>

<main>
  <form class="card" onsubmit={submit}>
    <div>
      <h1>{mode === 'setup' ? 'Set up Home AI' : 'Sign in'}</h1>
      {#if mode === 'setup'}
        <p class="muted small">
          Create the administrator account. The setup token was printed in the server's console when it started.
        </p>
      {/if}
    </div>

    {#if notice && mode === 'login'}<p class="ok small" role="status">{notice}</p>{/if}

    {#if mode === 'setup'}
      <label>
        Setup token
        <input type="text" bind:value={token} required autocomplete="off" spellcheck="false" />
      </label>
    {/if}
    <label>
      Username
      <input type="text" bind:value={username} required autocomplete="username" autocapitalize="none" spellcheck="false" />
    </label>
    <label>
      Password
      <input
        type="password"
        bind:value={password}
        required
        minlength={mode === 'setup' ? 12 : undefined}
        autocomplete={mode === 'setup' ? 'new-password' : 'current-password'}
      />
    </label>
    {#if mode === 'setup'}
      <label>
        Repeat password
        <input type="password" bind:value={confirm} required autocomplete="new-password" />
      </label>
      <p class="muted small">At least 12 characters.</p>
    {/if}

    {#if error}<p class="bad small" role="alert">{error}</p>{/if}

    <button class="primary" disabled={busy}>
      {busy ? 'Please wait…' : mode === 'setup' ? 'Create administrator' : 'Sign in'}
    </button>
  </form>
</main>

<style>
  main {
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 20px;
  }
  form {
    width: 100%;
    max-width: 380px;
    display: grid;
    gap: 14px;
    padding: 28px;
  }
  form > div {
    display: grid;
    gap: 6px;
  }
</style>
