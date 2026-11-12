# Architecture and engineering decisions

## Runtime design
Use one compiled Rust binary containing: HTTP API, auth/session manager, device registry, connector manager, authorization policy, typed action executor, event bus, deterministic automation scheduler, audit logger, persistence, resource monitoring, and optional AI orchestration client.

UI: build Svelte/TypeScript to static assets in CI or developer computer; serve from Rust app. Real-time channel: authenticated WebSocket, with reconnect and full-state resync. Persistence: SQLite with WAL and bounded history; schema migrations. Linux service: native systemd. Optional isolated subprocesses for heavyweight voice services or untrusted extensions.

## Control flow
Web or AI request -> authenticate user/session -> resolve room/device and documented capability -> validate inputs -> policy/risk check -> require confirmation if needed -> connector action -> verify state/acknowledgement -> publish event -> persist audit -> update clients -> report confirmed/failed/unknown status.

## Connector contract
Include lifecycle `initialize/connect/disconnect/discover/read/subscribe/execute/health/dispose`, capability manifest, authentication/config schema, typed events, safe retries, deadlines and bounded queues. Built-in trusted connectors can be native Rust; third-party connectors use versioned process protocol rather than unstable Rust dynamic ABI. Deduplicate aliases and underlying devices discovered twice.

## Core architectural constraints
- Never let LLM output directly execute shell commands or arbitrary HTTP destinations.
- Use official vendor docs and model-specific capability detection.
- No assumption that an Apple HomeKit bridge can read existing devices from an Apple Home household.
- Do not run Redis, Kubernetes, a message broker or numerous microservices without measured need.
- Separate monitored resource readings from supported management actions.

## Build portability
Cross-build/test for baseline x86-64 Linux without newer instruction sets; do not use `target-cpu=native` on development machine. Build frontend off-device. CI should run unit and integration tests, lint and formatting; a real Mac mini smoke test is required before claiming hardware compatibility.

## Decisions to record as ADRs
TLS setup on LAN; exact Rust crates; session storage; connector isolation mechanism; storage format/retention; OS boot mode; backup/rollback mechanism; voice approach; Apple Home architecture; router vendor integration.
