# Implementation roadmap and session handoff

Track actual code and test evidence. **No milestone is marked complete by writing documentation alone.**

## M0 — repository and feasibility [IN PROGRESS — Rust never compiled, see handoff]
- Initialize Rust and Svelte project; lock supported toolchain versions.
- Confirm Core 2 Duo CPU baseline and Debian boot caveats with non-destructive compatibility plan.
- Add CI formatting, linting and unit test jobs.
- Implement a hardware-diagnostic CLI with mock outputs and safe read-only operation.
Acceptance: CI builds baseline release, tests run, hardware report makes unknown data explicit.

## M1 — secure usable core [IN PROGRESS — code written, Rust untested, see handoff]
- Rust HTTP service; SQLite migrations; first-run local admin bootstrap; secure login/session; API auth.
- Simulated device registry; typed command policy; audit events.
- Static Svelte UI served by Rust: login, overview, server stats, simulator control.
- Authenticated WebSocket with reconnect/state refresh.
Acceptance: first login works; unauthorized control denied; simulator state changes live; restart preserves state.

## M2 — connectors and actions [NOT STARTED]
- Connector SDK and lifecycle, status/error reporting and contract tests.
- Implement Loxone connector against official docs; real-device testing when available.
- Implement HEOS/Denon and Spotify using approved interfaces.
Acceptance: per-device action outcomes verified; offline connector doesn't crash core; mock/real status distinguished.

## M3 — wider interoperability [NOT STARTED]
- Apple Home viable architecture + optional HA interoperability adapter.
- Yale supported connector only after exact lock/hub model identified.
- Network monitoring and router adapters.
Acceptance: capability support/limitations documented; high-risk action confirmation tested.

## M4 — AI and automations [NOT STARTED]
- Cloud AI adapter and structured tools, action authorization, multi-step reporting.
- Deterministic, persistent rule scheduler; offline-safe scenes.
- Conversational memory: user-approved, visible, editable and deletable; never grants security-sensitive permissions (prompts/05 §7).
- Personality and humor levels 0-4 as AI style configuration, suppressed for security, emergencies and failures (prompts/05 §4-6).
Acceptance: typed tool requests verified; partial failure clear; automations operate with AI provider disconnected.

## M4b — voice, wake word and speech [NOT STARTED]
Full requirements: `prompts/05-VOICE-PERSONALITY-HUMOR.md`. Depends on M4.
- Voice-client protocol (authenticated, per-room identity) and a first client; listening off until an admin enables it per client.
- Local wake word ("Jarvis") on the client, VAD, follow-up window, barge-in; cached acknowledgment audio with no AI call.
- Provider-independent STT and expressive neural TTS with streaming; English and Norwegian; capability flags per provider.
- Voice & Personality settings page with preview, routing, health and diagnostics; music ducking with safe volume restore.
- Voice runs as an independently restartable, resource-limited service that cannot block the core.
Acceptance: the 15 tests in prompts/05 §11. Tests 1-6, 14 and 15 need real microphones, speakers, a TTS provider and the Mac mini; they stay NOT TESTED until run on hardware.
## M5 — production readiness [NOT STARTED]
- Harden TLS, secrets, backups/restore, update/rollback, resource limits, performance benchmarking.
- Test on actual Mac mini with correct instruction set and Linux boot mode.
Acceptance: deployed 24/7 smoke test, real metrics, off-device restore test, full docs.

## Session handoff record
After each session append dated lines with: milestone, files changed, tests run with result, blockers, next single action. Never imply a task is complete without actual execution results.

### 2026-11-12 — M0/M1 first slice written; Rust side NOT compiled or tested
- **Files:** `Cargo.toml`, `rust-toolchain.toml` (1.99.1), `.cargo/config.toml` (x86-64 baseline), `server/` (Rust core + `tests/api.rs`), `web/` (Svelte dashboard), `.github/workflows/ci.yml`, `docs/adr/0001-foundation.md`, `prompts/`.
- **Ran and passed:** `cargo fmt --all` (exit 0; proves the Rust parses, nothing more). `npm run check`: 0 errors, 0 warnings. `npm run build`: OK, 65 kB JS / 5 kB CSS.
- **Did not run:** `cargo build`, `cargo clippy`, `cargo test`. No Rust in this repository has ever been compiled. Expect compile and lint errors on the first real build. The dashboard has never been run against the server. Acceptance tests A01–A07 are written in `server/tests/api.rs` but have produced no evidence. A08 needs the Mac mini.
- **Blocker:** the development PC (Windows 11) has an Application Control policy that blocks locally compiled executables (Cargo build scripts fail with OS error 4551). The policy was left as is. Rust must be built somewhere else: CI, WSL/Linux, or another machine.
- **Not done in M0:** Debian boot plan for Macmini4,1; CI has never executed.
- **Not done in M1:** user management, MFA, TLS proxy configuration.
- **Next single action:** get one green CI run (push to GitHub so `.github/workflows/ci.yml` runs), then fix whatever the compiler, clippy and the tests report.
