<script lang="ts">
  import { api, ApiError, type VoiceResult } from '../lib/api';

  let text = $state('');
  let busy = $state(false);
  let error = $state('');
  let history = $state<{ said: string; result: VoiceResult }[]>([]);

  async function send(e: SubmitEvent) {
    e.preventDefault();
    const said = text.trim();
    if (!said || busy) return;
    busy = true;
    error = '';
    try {
      const result = await api.voice(said);
      history = [{ said, result }, ...history].slice(0, 5);
      text = '';
    } catch (err) {
      error = err instanceof ApiError ? err.message : 'Something went wrong.';
    } finally {
      busy = false;
    }
  }

  const good = (o: VoiceResult['outcome']) => o === 'confirmed' || o === 'answer';
</script>

<section class="card voice">
  <h2>Say it</h2>
  <p class="muted small">
    Type a command, for example “turn off the kitchen light”, “set the thermostat to twenty two”,
    “volume up” or “what is the temperature in the bedroom”. Microphone input is not connected yet.
    Unlocking is never done by voice.
  </p>
  <form onsubmit={send}>
    <label class="sr" for="voice-text">Command</label>
    <input
      id="voice-text"
      type="text"
      bind:value={text}
      maxlength="300"
      autocomplete="off"
      placeholder="Turn on the living room light"
    />
    <button type="submit" disabled={busy || text.trim() === ''}>{busy ? 'Working…' : 'Send'}</button>
  </form>
  {#if error}<p class="warn" role="alert">{error}</p>{/if}
  {#if history.length > 0}
    <ul aria-live="polite">
      {#each history as h, i (i)}
        <li>
          <span class="muted small">You: {h.said}</span>
          <span class:warn={!good(h.result.outcome)}>{h.result.reply}</span>
        </li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  .voice {
    display: grid;
    gap: 10px;
    margin-bottom: 28px;
  }
  form {
    display: flex;
    gap: 8px;
  }
  input {
    flex: 1;
    min-width: 0;
  }
  ul {
    list-style: none;
    padding: 0;
    margin: 0;
    display: grid;
    gap: 8px;
  }
  li {
    display: grid;
    gap: 2px;
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip: rect(0 0 0 0);
  }
</style>
