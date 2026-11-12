<script lang="ts">
  import { api, ApiError, bytes, type HomeSettings, type ServerInfo, type User } from '../lib/api';
  import { live } from '../lib/live.svelte';
  import { prefs } from '../lib/prefs.svelte';

  let {
    resume,
    onadmin,
    ondone,
  }: {
    /** True when an administrator exists and is signed in but never finished. */
    resume: boolean;
    onadmin: (u: User) => void;
    ondone: () => void;
  } = $props();

  const STEPS = [
    'Welcome',
    'Administrator',
    'Home',
    'AI provider',
    'Voice',
    'Integrations',
    'Devices',
    'Security',
    'Finish',
  ] as const;
  const HOME_STEP = 2;

  // Only the starting step depends on `resume`; later changes must not reset it.
  // svelte-ignore state_referenced_locally
  let step = $state(resume ? HOME_STEP : 0);
  let busy = $state(false);
  let error = $state('');

  // Step 1
  let token = $state('');
  let server = $state<ServerInfo | null>(null);

  // Step 2
  let username = $state('');
  let password = $state('');
  let confirm = $state('');

  // Step 3
  const browserZone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  const zones: string[] =
    typeof Intl.supportedValuesOf === 'function' ? Intl.supportedValuesOf('timeZone') : [browserZone, 'UTC'];
  let home = $state<HomeSettings>({
    home_name: 'Home',
    country: '',
    timezone: browserZone,
    language: 'en',
    temperature_unit: 'celsius',
    rooms: ['Living room', 'Kitchen', 'Bedroom', 'Hallway'],
  });
  let roomsText = $state('Living room\nKitchen\nBedroom\nHallway');
  let homeLoaded = false;

  // Step 8
  let sessionHours = $state(12);
  let securityLoaded = false;

  const PLANNED = ['Loxone', 'Apple Home', 'Home Assistant', 'Denon / HEOS', 'Spotify', 'Yale', 'Network monitoring'];

  function message(e: unknown) {
    return e instanceof ApiError ? e.message : 'Something went wrong.';
  }

  async function guard(fn: () => Promise<void>) {
    error = '';
    busy = true;
    try {
      await fn();
    } catch (e) {
      error = message(e);
    } finally {
      busy = false;
    }
  }

  // Load saved values when arriving at a step that edits them.
  $effect(() => {
    if (step === HOME_STEP && !homeLoaded) {
      homeLoaded = true;
      api
        .getHome()
        .then(({ home: saved }) => {
          // Keep the browser's time zone as the suggestion on a fresh install.
          if (saved.timezone === 'UTC' && saved.home_name === 'Home') saved.timezone = browserZone;
          home = saved;
          roomsText = saved.rooms.join('\n');
        })
        .catch(() => {});
    }
    if (step === 7 && !securityLoaded) {
      securityLoaded = true;
      api
        .getSecurity()
        .then(({ security }) => (sessionHours = security.session_hours))
        .catch(() => {});
    }
  });

  const verifyToken = (e: SubmitEvent) => {
    e.preventDefault();
    guard(async () => {
      server = (await api.setupVerify(token.trim())).server;
    });
  };

  const createAdmin = (e: SubmitEvent) => {
    e.preventDefault();
    if (password !== confirm) {
      error = 'The two passwords do not match.';
      return;
    }
    guard(async () => {
      const user = await api.setup(token.trim(), username, password);
      token = password = confirm = '';
      onadmin(user);
      step = HOME_STEP;
    });
  };

  const saveHome = (e: SubmitEvent) => {
    e.preventDefault();
    guard(async () => {
      const saved = (await api.putHome({ ...home, rooms: roomsText.split('\n') })).home;
      home = saved;
      roomsText = saved.rooms.join('\n');
      prefs.home = saved;
      step += 1;
    });
  };

  const saveSecurity = (e: SubmitEvent) => {
    e.preventDefault();
    guard(async () => {
      sessionHours = (await api.putSecurity({ session_hours: sessionHours })).security.session_hours;
      step += 1;
    });
  };

  const finish = () =>
    guard(async () => {
      await api.finishSetup();
      ondone();
    });

  const next = () => {
    error = '';
    step += 1;
  };
  const back = () => {
    error = '';
    // The administrator step cannot be revisited once the account exists.
    if (step > HOME_STEP) step -= 1;
  };
</script>

<main>
  <div class="card shell">
    <header>
      <p class="muted small">Step {step + 1} of {STEPS.length}</p>
      <h1>{STEPS[step]}</h1>
      <div class="bar" role="progressbar" aria-valuemin="1" aria-valuemax={STEPS.length} aria-valuenow={step + 1}>
        <span style:width={`${((step + 1) / STEPS.length) * 100}%`}></span>
      </div>
    </header>

    {#if step === 0}
      <div class="lead">
        <h2>Welcome to JARVIS.</h2>
        <p>Your intelligent home management system.</p>
        <p class="muted">Let's configure your new home AI.</p>
      </div>
      {#if !server}
        <form onsubmit={verifyToken}>
          <label>
            One-time setup token
            <input type="text" bind:value={token} required autocomplete="off" spellcheck="false" />
          </label>
          <p class="muted small">
            The installer printed it in the server's terminal. Lost it or expired? Run
            <code>sudo home-ai setup-token</code> on the server.
          </p>
          {#if error}<p class="bad small" role="alert">{error}</p>{/if}
          <div class="actions"><button class="primary" disabled={busy}>{busy ? 'Checking…' : 'Continue'}</button></div>
        </form>
      {:else}
        <dl>
          <dt>Server</dt><dd>{server.host_name ?? 'Unknown'}</dd>
          <dt>System</dt><dd>{server.os || 'Unknown'}</dd>
          <dt>Processor</dt><dd>{server.cpu_model || 'Unknown'} ({server.logical_cores} cores)</dd>
          <dt>Memory</dt><dd>{bytes(server.mem_total_bytes)}</dd>
          <dt>Home AI</dt><dd>version {server.version}</dd>
        </dl>
        <div class="actions"><button class="primary" onclick={next}>Start setup</button></div>
      {/if}
    {:else if step === 1}
      <form onsubmit={createAdmin}>
        <p class="muted small">This account has full control of the server. There is no default password.</p>
        <label>
          Administrator username
          <input type="text" bind:value={username} required autocomplete="username" autocapitalize="none" spellcheck="false" />
        </label>
        <label>
          Password (at least 12 characters)
          <input type="password" bind:value={password} required minlength="12" autocomplete="new-password" />
        </label>
        <label>
          Repeat password
          <input type="password" bind:value={confirm} required autocomplete="new-password" />
        </label>
        <p class="muted small">Passkeys and two-step sign-in are not available in this version.</p>
        {#if error}<p class="bad small" role="alert">{error}</p>{/if}
        <div class="actions"><button class="primary" disabled={busy}>{busy ? 'Creating…' : 'Create administrator'}</button></div>
      </form>
    {:else if step === 2}
      <form onsubmit={saveHome}>
        <label>
          Home name
          <input type="text" bind:value={home.home_name} required maxlength="60" />
        </label>
        <div class="two">
          <label>
            Country code (optional)
            <input type="text" bind:value={home.country} maxlength="2" placeholder="NO" autocapitalize="characters" />
          </label>
          <label>
            Time zone
            <select bind:value={home.timezone}>
              {#each zones as z (z)}<option value={z}>{z}</option>{/each}
            </select>
          </label>
        </div>
        <div class="two">
          <label>
            Preferred language
            <select bind:value={home.language}>
              <option value="en">English</option>
              <option value="nb">Norsk (bokmål)</option>
            </select>
          </label>
          <label>
            Temperature unit
            <select bind:value={home.temperature_unit}>
              <option value="celsius">Celsius (°C)</option>
              <option value="fahrenheit">Fahrenheit (°F)</option>
            </select>
          </label>
        </div>
        <label>
          Rooms, one per line
          <textarea bind:value={roomsText} rows="5"></textarea>
        </label>
        <p class="muted small">
          The temperature unit applies to the dashboard now. The language is saved as your preference, but the dashboard
          is English only for now. Rooms are saved for when devices can be assigned to them.
        </p>
        {#if error}<p class="bad small" role="alert">{error}</p>{/if}
        <div class="actions"><button class="primary" disabled={busy}>{busy ? 'Saving…' : 'Save and continue'}</button></div>
      </form>
    {:else if step === 3}
      <p><span class="badge">Not available in this version</span></p>
      <p>The AI assistant is not built yet, so there is no provider to configure.</p>
      <p class="muted small">
        Home AI does not need one to work: the dashboard and device control run on this server. When the assistant
        exists, you will add Anthropic, OpenAI or a compatible provider here, and can leave it out.
      </p>
      <div class="actions"><button onclick={back}>Back</button><button class="primary" onclick={next}>Skip</button></div>
    {:else if step === 4}
      <p><span class="badge">Not available in this version</span></p>
      <p>Voice, the "Jarvis" wake word, and personality and humor settings are not built yet.</p>
      <p class="muted small">
        When they are: a browser can only use your microphone with your permission and while this page is open. It
        cannot listen reliably in the background. Hands-free use around the home needs dedicated room devices.
      </p>
      <div class="actions"><button onclick={back}>Back</button><button class="primary" onclick={next}>Skip</button></div>
    {:else if step === 5}
      <ul class="list">
        <li><span>Simulator</span><span class="ok small">Installed</span></li>
        {#each PLANNED as name (name)}
          <li><span>{name}</span><span class="muted small">Not available yet</span></li>
        {/each}
      </ul>
      <p class="muted small">No real connector exists yet. The simulator provides test devices so the dashboard can be tried.</p>
      <div class="actions"><button onclick={back}>Back</button><button class="primary" onclick={next}>Continue</button></div>
    {:else if step === 6}
      {#if live.devices.length === 0}
        <p class="muted">{live.connected ? 'No devices found.' : 'Connecting to the server…'}</p>
      {:else}
        <ul class="list">
          {#each live.devices as d (d.id)}
            <li>
              <span>{d.name} <span class="muted small">· {d.room}</span></span>
              {#if d.simulated}<span class="badge">Simulated</span>{/if}
            </li>
          {/each}
        </ul>
      {/if}
      <p class="muted small">
        These come from the simulator, not from real hardware. Renaming, room assignment, grouping and duplicate
        handling are not available yet.
      </p>
      <div class="actions"><button onclick={back}>Back</button><button class="primary" onclick={next}>Continue</button></div>
    {:else if step === 7}
      <form onsubmit={saveSecurity}>
        <label>
          Stay signed in for (hours, 1–168)
          <input type="number" bind:value={sessionHours} min="1" max="168" required />
        </label>
        <p class="muted small">Applies to sign-ins from now on.</p>
        <ul class="facts small">
          <li>Unlocking a door needs an administrator and their password again. This cannot be switched off.</li>
          <li>Read-only accounts can view devices but not control them.</li>
          <li>Remote access from outside your network: not available. The server is reachable on your local network only if your router does not forward it.</li>
          <li>Voice permissions and backup preferences: not available in this version.</li>
        </ul>
        {#if error}<p class="bad small" role="alert">{error}</p>{/if}
        <div class="actions">
          <button type="button" onclick={back}>Back</button>
          <button class="primary" disabled={busy}>{busy ? 'Saving…' : 'Save and continue'}</button>
        </div>
      </form>
    {:else}
      <dl>
        <dt>Home</dt><dd>{home.home_name} · {home.timezone}</dd>
        <dt>Integrations</dt><dd>Simulator only</dd>
        <dt>Devices</dt><dd>{live.devices.length} ({live.devices.filter((d) => d.simulated).length} simulated)</dd>
        <dt>AI provider</dt><dd>Not configured (not available yet)</dd>
        <dt>Voice</dt><dd>Off (not available yet)</dd>
        <dt>Sign-in length</dt><dd>{sessionHours} hours</dd>
        <dt>Live connection</dt>
        <dd class:ok={live.connected} class:warn={!live.connected}>{live.connected ? 'Connected' : 'Not connected'}</dd>
      </dl>
      {#if error}<p class="bad small" role="alert">{error}</p>{/if}
      <div class="actions">
        <button onclick={back}>Back</button>
        <button class="primary" onclick={finish} disabled={busy}>{busy ? 'Finishing…' : 'Finish setup'}</button>
      </div>
    {/if}
  </div>
</main>

<style>
  main {
    min-height: 100vh;
    display: grid;
    place-items: center;
    padding: 20px;
  }
  .shell {
    width: 100%;
    max-width: 560px;
    display: grid;
    gap: 18px;
    padding: 28px;
  }
  header {
    display: grid;
    gap: 8px;
  }
  .lead {
    display: grid;
    gap: 4px;
  }
  form {
    display: grid;
    gap: 14px;
  }
  .two {
    display: grid;
    gap: 14px;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  }
  select,
  textarea,
  input[type='number'] {
    font: inherit;
    color: inherit;
    width: 100%;
    padding: 10px 12px;
    border-radius: 10px;
    border: 1px solid var(--border);
    background: var(--surface-solid);
  }
  textarea {
    resize: vertical;
  }
  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
  dl {
    display: grid;
    grid-template-columns: max-content 1fr;
    gap: 8px 18px;
    margin: 0;
  }
  dt {
    color: var(--muted);
  }
  dd {
    margin: 0;
    overflow-wrap: anywhere;
  }
  .list {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .list li {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    padding: 10px 0;
    border-bottom: 1px solid var(--border);
  }
  .facts {
    margin: 0;
    padding-left: 18px;
    color: var(--muted);
    display: grid;
    gap: 6px;
  }
  code {
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 0.9em;
  }
</style>
