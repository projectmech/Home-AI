# ADR 0005 — Voice: host, clients and room units

Status: accepted 2026-11-13 (owner's choices: Mac mini is the host only; fast and responsive; hybrid local + cloud).

## Context
The Mac mini (Core 2 Duo, no AVX) is the host. Real microphones and speakers live in the home, on clients. Voice must feel fast.

## Decision
- **Host (Rust core):** command understanding, the device-action policy, the audit log, authenticated audio connections. Speech engines run as separate sandboxed processes called by the core.
- **Clients:** (1) a web app (PWA) served by the host, first with typed input, then push-to-talk; (2) room units (Raspberry Pi Zero 2 W with a microphone array, or a USB speakerphone on a Pi, or an ESP32-S3 box) that listen for the wake word locally and stream audio to the host only after it. Each client pairs once with a one-time code and can be revoked by an admin. Always-listening is a room-unit feature: phone browsers cannot listen in the background.
- **Hybrid speech:** the wake word and home-control commands are recognised locally (streaming, small vocabulary, offline, instant). Open-ended questions may go to cloud speech/AI, as an opt-in setting; the owner knows those words leave the home.
- **Open source candidates:** Piper (speech output), a streaming small-vocabulary recogniser such as Vosk (commands), whisper.cpp (optional free-form, slow on this CPU), openWakeWord. Each must pass a run under `-cpu Penryn` in CI before it is adopted.
- **Command understanding is a fixed grammar in Rust (`server/src/voice.rs`)**, not an AI. It yields one typed `Action`, which goes through the same validation, permission and audit path as a button press (`run_device_action`). The AI only ever proposes; the policy decides.
- **Voice never unlocks.** A spoken request does not prove who is speaking. Unlock stays on the dashboard with password confirmation.
- **Privacy:** the transcript is not stored or logged; only that a voice command ran and its outcome are audited.

## Slice 1 (built)
`POST /api/voice/command {text}` → reply and outcome; Home page "Say it" box (typed). Grammar: lights (on/off, brightness), thermostat, speaker (play/pause, volume up/down/to N), lock, temperature questions; spoken number words ("twenty two", "one hundred"); one device at a time; ambiguity is asked back, never guessed.

## Not built yet
Audio transport and pairing; the local recogniser and wake word; speech output; room-unit software; cloud opt-in; per-user voice identity; multi-device ("all the lights"); rooms from the home settings in the grammar.
