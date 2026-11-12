# Claude Code instructions — Home AI

Build an independent, self-hosted JARVIS-like home assistant with a **custom Rust core** and an authenticated Svelte/TypeScript web UI. The target device is a **2010 Mac mini, Core 2 Duo, 16 GB DDR3, 256 GB drive of unknown type**. Primary OS candidate: Debian 13 minimal, subject to successful hardware/boot verification.

## First read
Read `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/HARDWARE.md`, `docs/SECURITY.md`, `docs/ROADMAP.md`, and `docs/OPEN_QUESTIONS.md`. Read integration-specific documentation **when implementing that connector**, not all at once. Treat the documents as authoritative project requirements, not assertions that code already exists.

## Non-negotiable decisions
- Native Rust modular monolith for server, device registry, events, automations, action authorization and API; compiled Svelte frontend served by Rust; SQLite storage; WebSockets for live state.
- No Home Assistant as the core. An optional connector to Home Assistant is allowed.
- AI generates **proposed structured actions**; Rust authorization and tool execution decide whether they can occur. No unrestricted AI shell/network access. High-risk actions require step-up authentication/confirmation.
- Loxone, Apple Home interoperability, Denon/HEOS, Spotify, Yale and LAN monitoring are connector targets; never invent undocumented APIs or capabilities.
- The Mac mini is for deployed runtime, **not for routine compiling**. Use a conservative x86-64 target compatible with Core 2 Duo (no AVX, AVX2 or newer x86-64 baseline).
- Cloud AI for demanding reasoning; local deterministic home control and automation must work when internet or AI is down.
- Never commit secrets, private device identifiers, API keys, pairing codes or OAuth tokens. Use redacted fixtures and `.env.example`.
- Never claim physical-device integration is tested unless actual hardware tests occurred.

## Working method
1. Read relevant spec and roadmap milestone; inspect codebase before changing it.
2. Write a short implementation plan with acceptance tests.
3. Implement **one working vertical slice** (backend + frontend + tests) at a time.
4. Run formatting, linting, tests and compatibility checks; report exact pass/fail results.
5. Update `docs/ROADMAP.md` with progress, unresolved blockers and next step.
6. Capture decisions and tradeoffs in `docs/ARCHITECTURE.md` or `docs/adr/`.
7. Ask only about user-specific unknown hardware/capabilities that materially block the next step. Use simulators until real devices are available.

## Initial scope
First prove: hardware report -> native Rust app -> SQLite migration -> simulator -> first-time admin setup -> secure login -> authenticated WebSocket dashboard -> device action policy -> verified simulator command. Only then implement one physical connector at a time.
