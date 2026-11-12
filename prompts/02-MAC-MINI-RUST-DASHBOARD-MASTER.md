# PROJECT: CUSTOM SELF-HOSTED JARVIS HOME AI — MAC MINI / RUST MASTER PROMPT

> This is the hardware-specific master prompt. It **overrides prompt 01** on backend technology, deployment, and implementation priorities. Read prompt 03 afterward for storage and optimization overrides.

## ROLE AND OBJECTIVE

You are Claude Fable 5.2, acting as a senior systems programmer, Rust engineer, embedded systems architect, AI systems engineer, network engineer, and full-stack developer.

Build a complete, highly optimized, self-hosted AI home-management system inspired by JARVIS. The system runs 24/7 on a 2010 Mac mini. **Develop the application's core engine yourself**, optimized for low resource consumption and high performance. Do not build a Home Assistant reskin, Node-RED installation, or existing automation platform with AI bolted on. Build an independent unified application.

It must include a custom server core, AI orchestration, secure website with login, server-administration dashboard, device management, Loxone, Apple Home interoperability, Denon/HEOS, Spotify, Yale, network monitoring and management, voice, automations, real-time monitoring, and an extensible connector framework. Essential home-control operations remain functional if the AI provider is offline.

## 1. TARGET HARDWARE

- Model: Apple Mac mini Mid 2010 (Macmini4,1).
- RAM: 16 GB DDR3.
- CPU: Intel Core 2 Duo; detect exact model.
- Architecture: x86-64.
- GPU: legacy NVIDIA integrated graphics, not a modern accelerator.
- Network: Gigabit Ethernet.
- Internal storage: 256 GB reported, SSD versus mechanical HDD unknown; prompt 03 describes detection.
- OS: lightweight headless Linux server.

This is old hardware and performance optimization is mandatory. No AVX or AVX2 requirements, no assumed CUDA GPU, no assumed modern CPU-specific instructions. Check every native dependency for target compatibility.

During installation detect CPU model/features, core count, RAM, drive type/capacity/free space, network interfaces, OS and kernel. Generate a compatibility report and choose safe defaults. Never enable unsupported CPU instructions.

## 2. OPERATING SYSTEM

Prefer Debian 13 minimal; Ubuntu Server 24.04 LTS minimal is the fallback. Evaluate idle RAM, CPU overhead, maintenance, security support, drivers, booting, Rust support. No graphical desktop, headless SSH and authenticated web dashboard only.

Account for old Apple EFI and legacy boot compatibility. Prefer wired Ethernet over aging Wi-Fi. Produce reproducible installation documentation for partitioning, boot, networking, SSH, automatic start, secure updates, restart after power failure, recovery, and backup. Do not erase disks or modify boot partitions automatically; require explicit confirmation for destructive actions.

## 3. CUSTOM HIGH-PERFORMANCE CORE

**Critical requirement: write a custom independent core, not a Home Assistant-based system.**

Responsibilities: devices, rooms, connectors, users, permissions, AI requests, automations, events, real-time synchronization, network monitoring, health, configuration, dashboard APIs.

### 3.1 Language

Use **Rust**, with mature maintained libraries such as Tokio and Axum when appropriate. Prefer native compiled performance, low overhead, efficient concurrency and memory safety. Use established security, TLS, authentication, and database libraries. Custom core does not mean writing cryptography, HTTP parsers, or TLS implementations from scratch.

### 3.2 Architecture

Prefer a modular monolith: one native executable where practical, with clear internal interfaces for:

- Core Runtime
- Device Registry
- Connector Manager
- AI Orchestrator
- Automation Engine
- Event Bus
- Authentication and Authorization
- Network Monitoring
- Notification Engine
- System Monitoring
- Configuration Manager
- Web API and WebSocket Server
- Audit Logger
- Scheduler

Avoid unnecessary independent services, message brokers, container orchestration and multiple databases.

### 3.3 Execution Model

Use asynchronous nonblocking I/O, bounded work queues, configurable concurrency, efficient events, cancellation, deadlines, error propagation and graceful shutdown. Avoid busy-waiting, unnecessary threads, unbounded retries, and failure propagation across independent connectors. A long AI call or failed integration must not block core device control.

## 4. PERFORMANCE OPTIMIZATION

This machine has two physical CPU cores. Minimize CPU rather than optimizing only RAM.

Implement event subscriptions over repeated polling, adaptive polling, event batching, request deduplication, bounded tasks, idle task suspension, rate limits, efficient timeouts, cached metadata, batched database writes and lightweight serialization. Avoid waking the CPU for no reason.

Set an **engineering benchmark target**, not a promise, for core/database idle resident memory below roughly 300 MB excluding OS, optional voice, AI models, and connector processes. Measure real use. Bound queues, logs and caches.

Use SQLite: indexed prepared statements, transactions, schema migrations, WAL where appropriate, rotation, retention, integrity, reliable backups. Avoid unnecessary writes especially if HDD. Centralize scheduling for network health, devices, reconnect, metrics, and maintenance instead of separate high-frequency loops.

## 5. AI ORCHESTRATION CORE

Implement AI orchestration in the custom platform, **separate from the language model**. Handle conversations, context, device identification, tool selection, planning, errors, user-approved preferences and memory, and automation generation.

AI proposes actions; independent Rust authorization/execution engine validates and executes.

Support adapters for Anthropic, OpenAI, optional compatible local model endpoints. Configure provider/API keys in protected dashboard settings; never send API secrets to frontend.

Mac mini's Core 2 Duo is not suitable for large local LLMs. Default to external inference. Keep device control, state, security, automations, scheduling, network and events local. Optional lightweight deterministic commands such as "turn on kitchen lights" are permitted when unambiguous and fully authorized, without requiring cloud inference. Provide future support for small local models only after CPU compatibility and latency benchmarks.

## 6. ADMINISTRATION WEBSITE

**Major requirement:** fully functional secure browser-based website for other machines and phones on the LAN. Headless Mac mini must not require a monitor once installed.

### 6.1 Frontend

Use Svelte + TypeScript; compile static frontend served by Rust. Do not run a separate production Node.js server. Use modern lightweight CSS and component architecture.

Visual direction: modern Apple-like, clean typography, dark/light, white/black/dark gray palette, subtle liquid-glass-like transparency, soft borders, smooth but inexpensive animations, rounded cards, minimal icons, responsive desktop/tablet/phone. Avoid gaming-style neon.

### 6.2 Secure Login

Unauthenticated visitors see only login. Provide username/email, password, login, clear errors, secure sessions, expiration, logout, rate limiting, safe account lockout safeguards, optional passkeys and MFA.

Use Argon2id password hashing, HTTP-only secure cookies, CSRF/session fixation/bruteforce/privilege-escalation protection. Require HTTPS for authenticated access; use a documented trusted local certificate method. Never silently downgrade to HTTP.

### 6.3 First Run

First-time wizard: create admin, server name, network, AI, timezone, first connector, device discovery, room assignments, security, completion. Restrict initial setup to authorized local operator and close bootstrap mode afterward. No default permanent administrator password.

## 7. SERVER ADMINISTRATION DASHBOARD

The website must offer actual application administration and underlying machine observability.

### 7.1 Overview

Server status, uptime, CPU, RAM, disk, network traffic, OS, CPU model, app version, connected device count, active connectors, AI provider status, errors, automations. Real-time updates.

### 7.2 Performance Monitoring

CPU current/per-core/load/history; RAM total/used/available/application/swap; disk capacity/free/utilization/database/backups/SMART where supported; network interface/IP/upload/download/gateway/internet/errors; temperature/fan/thermal warnings if reliably available. Never fabricate hardware metrics.

### 7.3 Operating Profiles

Eco, Balanced (default), Performance profiles adjust only safe application-level settings: metrics rate, polling, caches, background concurrency, optional voice, and retention. Do not alter CPU voltage/firmware or weaken security.

### 7.4 Service Management

Admin-only service health, controlled restarts, connector restart, supervised app restart, logs, diagnostic export, backups, pending updates. **No arbitrary root shell in dashboard.**

### 7.5 Logs

Search/filter logs: system, connectors, device actions, automations, AI, network, authentication, errors; severity/source/date/device/connector/event filters. Redact secrets.

### 7.6 Updating

Version, available updates, notes, compatibility checks, backup status, progress, rollback availability. Require explicit authenticated approval and verify signed/trusted update artifacts, never run arbitrary fetched scripts.

## 8. CENTRAL HOME DASHBOARD

Separate navigation sections:

- **Home:** temperatures, lights, audio, Yale locks, network, scenes, notifications.
- **Rooms:** assign devices and directly control room functions.
- **Devices:** search/filter/rename/group/capabilities/online status.
- **Integrations:** connector setup and health.
- **Automations:** routines, logs, schedule.
- **AI:** conversational assistant, action confirmations.
- **Network:** devices, reachability and diagnostics.
- **Music:** Spotify, HEOS/Denon controls.
- **Server:** system administration.
- **Settings:** users, appearance, permission policies, settings.

Every relevant section must be functional, not just visual cards.

## 9. REAL-TIME DASHBOARD COMMUNICATION

Authenticated WebSockets for device changes, connector status, metrics, music, AI streaming, automation events, notifications, and command status. Use reconnect, heartbeat, event sequencing, resynchronization, bounded queues, safe slow-client handling. Avoid unnecessary polling. Ensure clients recover correct state after reconnection.

## 10. LOXONE CONNECTOR

Native supported local Loxone Miniserver integration: authenticated connection, configuration, rooms/devices, lights/brightness, heating/thermostats/temperatures, blinds/shutters, scenes and documented other controls, real-time updates, reconnection, command results, stable mapping. Review real protocol documentation. No fabricated commands or status.

## 11. APPLE HOME CONNECTOR

Apple Home interoperability with appropriate HomeKit/Matter, supported bridges, optional Apple-platform companion, optional Home Assistant API. Linux server cannot assume unrestricted access to an existing Apple Home database or pairing. Clearly distinguish controlling existing Apple Home accessories, independently pairing compatible accessories, and exposing bridge devices to Apple Home. Work with the supported capabilities; tolerate unavailable integrations.

## 12. DENON / HEOS CONNECTOR

Local discovery/manual IP, documented HEOS CLI and relevant Denon AVR protocols, connection management, playback status, play/pause, volume/mute, sources, grouping, metadata, queue if supported, receiver input if supported, real-time synchronization. Keep AVR and HEOS command differences clear.

## 13. SPOTIFY CONNECTOR

Proper OAuth flow, protected token storage, auth and refresh; search/playlists/play/pause/skip/playback state/device selection/transfer/queue only where the API and account permissions support it. Coordinate with HEOS via available supported Spotify Connect playback. Respect account eligibility, scopes, development-mode constraints, and DRM. No unauthorized streaming.

## 14. YALE LOCK CONNECTOR

Model-aware integration framework; use supported Yale Home/cloud, Matter, HomeKit, or bridge as required. Expose lock state, battery, connection, locking/unlocking, door state and history only when available. Unlock is high risk, requires verified login, separate authorization and confirmation. No unverified voice unlock and no prompt-injection-driven operations.

## 15. NETWORK CONNECTOR

Authorized local discovery and monitoring: IPs, names, reachability, last seen, gateway, DNS, internet, latency, packet loss and history. Efficient, bounded discovery; no aggressive scans. Connector capability framework for UniFi, MikroTik, OpenWrt, ASUS, Omada. Do not claim unsupported router metrics or actions.

## 16. CONNECTOR SDK

Custom modular system with typed methods initialize, authenticate, connect, disconnect, discover, read state, subscribe, execute, capabilities, health, reconfigure, dispose. Manifest includes versions, permissions, dependencies and config fields. Prefer native trusted built-ins; for third parties use isolated subprocess/IPC or similarly safe stable protocol rather than fragile Rust dynamic ABI. Disallow unrestricted plugin access and provide example connector and docs.

## 17. DEVICE REGISTRY

Single consistent registry: unique IDs, connector/external IDs, name, manufacturer, model, room, capabilities, state, connectivity, last update, actions, access rules. Duplicate reconciliation across connector views. Event-driven state updates. No implicit unsupported device actions.

## 18. AUTOMATION ENGINE

Build a **custom deterministic** engine, not Node-RED/Home Assistant automations. Triggers: time/schedule/state/sensor/network/manual; compound conditions, delays, timeouts, multi-action routines, logs. Scenes: Good Morning, Good Night, Movie Mode, Relax Mode, Away Mode. AI may suggest definitions, but enabling high-impact automation requires authorization. The LLM being offline must not stop existing rules.

## 19. VOICE SYSTEM

Optional modular browser microphone, STT/TTS, voice selection, Norwegian and English, optional configurable "Jarvis" wake word, future room voice satellites. The slow CPU means voice processing must never block essential control. Offer optional external speech providers; benchmark compatible lightweight local engines. Continuous listening disabled by default. Resource limits, privacy controls, user permissions.

## 20. AI ACTION EXECUTION

For a multi-device request: parse → identify devices → check capabilities → authorize → produce validated structured commands → execute per connector → confirm actual results → broadcast state → respond with per-action status. Never route raw model text to OS commands or devices, bypass policy, or hallucinate execution success.

## 21. USER MANAGEMENT AND PERMISSIONS

Administrator, Standard, Restricted, optional Guest. Backend-enforced per-capability read state, lights, heat, music, network info, automations, connectors, server admin, users, and high-risk lock control. Session records and audit trails.

## 22. SECURITY AND PRIVACY

TLS, Argon2id, trusted sessions, protected secrets, parameter validation, least-privilege services, rate limiting, logs, backups, prompt-injection defenses, per-tool authorization, no general shell exposed to browser/AI. Remote access disabled by default; offer private VPN if desired. No public device API endpoints by default. Keep sensitive state local where viable.

## 23. INSTALLATION AND DEPLOYMENT

Primary release format: **native Linux service**, managed by systemd, running as unprivileged user. Check OS/CPU/free space/dependencies; establish directories, migration, unit, startup, health. Require approval for host modifications. Avoid broad root permission; separate limited privileged helpers if needed. Docker optional only, not mandatory on old Mac mini.

## 24. SERVER HEALTH AND SELF-DIAGNOSTICS

Detect connector failures, congested event queues, DB errors, excessive CPU/memory, network outages, low disk, suspicious auth failures, AI outages, automation failures. Offer factual diagnostics and safe preapproved recovery operations. Never let AI invent and execute arbitrary repair shell commands.

## 25. OPTIMIZATION AND BENCHMARKING

Measure actual idle/peak CPU, idle memory, device command latency, WebSocket delay, DB throughput, dashboard load, connector reconnect, startup time, concurrent operations. Document measured values; optimize proven bottlenecks. Do not claim optimization without evidence.

## 26. DEVELOPMENT PHASES

1. Hardware evaluation, architecture, project init.
2. Rust core, DB, config, event system.
3. Auth, permissions, secure API.
4. Website, first-run admin login, live server dashboard.
5. Device registry and connector SDK.
6. Loxone.
7. HEOS, Denon, Spotify.
8. Apple Home interoperability/optional bridge.
9. Yale model-aware supported integration.
10. Network monitoring.
11. AI orchestration and conversation.
12. Automations and scenes.
13. Voice.
14. Performance benchmarking and optimization.
15. Security, reliability, installation, documentation.

Build complete vertical slices, test before extending, record gaps requiring hardware.

## 27. TESTING REQUIREMENTS

Unit, integration, API, auth, permissions, WebSocket, DB, automation, connector, failure recovery, benchmarking. Provide clearly labeled simulated lights, thermostats, speakers, locks, network devices and sensors. No simulated result presented as real physical integration testing.

## 28. DOCUMENTATION

Create README.md, ARCHITECTURE.md, HARDWARE.md, PERFORMANCE.md, INSTALLATION.md, SERVER_ADMINISTRATION.md, CONNECTORS.md, AI_ENGINE.md, VOICE.md, SECURITY.md, AUTOMATIONS.md, API.md, TROUBLESHOOTING.md, DEVELOPMENT.md, plus example config. Document installing, administering, login, Loxone, Apple Home-compatible devices, HEOS, Spotify, Yale, network, AI, automation, update, backup and restore.

## 29. FINAL ACCEPTANCE CRITERIA

Native binary starts on target ISA, DB initialized, secure login, working frontend, **real** server metrics, WebSockets, simulated controls, registry, connector failure isolation, AI with configured provider, tool permission enforcement, automations without AI, persistent settings, reliable service startup after reboot, documented installation, benchmark evidence. Each physical connector has independent real-device acceptance tests and explicit pending status until tested.

## 30. IMPORTANT INSTRUCTIONS AND FIRST TASK

Choose efficient maintainable technologies. Avoid unnecessary distributed stack, microservices, message brokers, containers, and multiple DBs. Write the independent Rust core. Never write custom cryptography or sacrifice safety/reliability for speed. Deliver working, tested backend plus polished frontend. Keep portable to newer Linux systems.

**Start now:** Inspect workspace; create roadmap and structure; implement and test this working sequence first:

1. Rust core starts.
2. Database initializes.
3. Website becomes available.
4. Secure first-run admin creation.
5. Authenticated login/logout.
6. Real server metrics in dashboard.
7. Simulated devices and state updates.
8. Authenticated WebSockets.
9. AI provider configuration.
10. Validated, authorized device commands.

Then add integrations in phased order, recording tests, progress and blockers. Ask only for unknown hardware/credentials genuinely necessary. Final objective: efficient, secure, modular 24/7 JARVIS system with custom Rust core and full authenticated administration website on Mac mini Mid 2010/16 GB RAM.
