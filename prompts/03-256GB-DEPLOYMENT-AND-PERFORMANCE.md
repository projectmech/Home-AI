# HARDWARE-SPECIFIC DEPLOYMENT AND PERFORMANCE ADDENDUM

> **Highest-priority instructions.** These instructions override the deployment, storage and performance assumptions in the prior master prompts.

## Confirmed hardware

- Primary server: Apple Mac mini Mid 2010.
- Processor: Intel Core 2 Duo, exact model unknown.
- RAM: 16 GB DDR3.
- Internal storage: Reported capacity of **256 GB**.
- Storage type: **Unknown**. Could be an SSD or mechanical HDD.
- Network: Prefer wired Gigabit Ethernet.
- Operating system: Prefer Debian 13 minimal, subject to real boot and driver testing.
- Application: Native custom Rust core with authenticated browser-based administration dashboard.

The server must operate continuously with low CPU usage, efficient memory management and controlled disk activity.

## 1. Hardware discovery

Before applying storage-specific optimization, detect the actual hardware. Implement an installation diagnostic utility that identifies:

- CPU model, available instruction sets, physical and logical cores.
- RAM and swap capacity.
- Drive manufacturer/model, capacity, rotational status.
- SMART status where available.
- Drive interface and negotiated speed.
- Filesystem, available storage.
- Boot mode, network interfaces and link speeds.

Do **not** assume a 256 GB drive is an SSD. If reported as SSD, verify filesystem/transport support before enabling optimization. Save the report in the admin dashboard.

## 2. Debian installation compatibility

This Mac mini uses older Apple firmware. Investigate correct installation and boot methods for **Macmini4,1**. Do not assume every Debian 13 installer works in EFI mode. There have been reports of EFI-related blank-screen installation problems on this model; legacy BIOS/CSM boot may work, but verify rather than promising that it will. Test installer media and boot compatibility before changing internal storage.

Never automatically erase the disk. Prefer minimal headless installation without desktop. Install only necessary SSH, network, TLS, monitoring, storage diagnostics, update and backup packages. Avoid background desktop processes.

## 3. Native Rust application

Build a native modular Rust server; prefer one optimized binary rather than many services. Use efficient async execution, bounded queues and minimal idle overhead.

Use conservative x86-64 target features. Do **not** compile with `target-cpu=native` on a newer development machine. Do not require AVX or AVX2 or newer x86-64 microarchitecture levels. Check runtime dependency compatibility.

Compile on a newer development computer or CI environment, producing a tested release binary compatible with the Core 2 Duo. Deploy that binary to the Mac mini. Do not require the full Rust toolchain, Node.js, frontend compiler, or heavy development dependencies in production. The Mac mini runs the app, not repeated builds.

## 4. Performance objectives

Treat these as **measured engineering targets, not promises**:

- Core idle CPU: aim for under 5% of total machine CPU capacity when normally idle, ignoring periodic monitoring spikes.
- Core idle RAM: aim for approximately 150–300 MB, subject to actual connector requirements.
- Device command latency: prioritize direct, responsive local operations.
- Dashboard requests: keep fast and avoid synchronous blocking work.
- AI: external inference must never block local device control.

Produce benchmark measurements; do not mark targets as achieved without evidence.

## 5. Disk optimization

**If SSD:** use suitable filesystem/database settings; enable scheduled TRIM only when supported; limit logs; batch writes; bound caches; monitor health.

**If mechanical HDD:** reduce unnecessary polling and writes; batch persisted events; avoid high-frequency history logging and excessive metadata updates; minimize separate writing services; rotate logs; monitor drive latency and health.

**Both:** SQLite transactions and prepared statements, indexes, disk space monitor, quotas, reliable off-device backups, healthy recovery checks. Never weaken database durability merely to save milliseconds.

## 6. Memory management

This machine has 16 GB RAM but a relatively slow CPU. Optimize CPU before using RAM for huge caches or LLMs. Bound queues and caches. Keep control service lightweight. Don't preload large local models. Avoid heavy monitoring platforms. Make optional modules independently disableable. Give voice processing separate resource constraints so it cannot interrupt home automations.

## 7. Resource-aware scheduling

Build one central scheduler rather than many rapid polling loops. Prefer connector push events. Initial configurable intervals:

- Real-time push: immediate when supported.
- Dashboard hardware metrics: every 5–15 seconds.
- Connectivity checks: every 30–60 seconds.
- Slow-changing device health: every 1–5 minutes.
- Full network discovery: manual or occasional scheduled scans.
- Database maintenance: during low activity.
- Backups: daily or administrator-selected schedule.

Reduce nonessential work when no browser clients are connected; never pause essential automations or device state listeners.

## 8. Database retention

Use SQLite with suitable WAL settings, controlled checkpoints, state-history write batching, data retention, rollups, indexed queries, log rotation.

Suggested initial defaults:

- Detailed server metrics: 7 days.
- Aggregated historical metrics: 90 days.
- Ordinary device events: 30 days.
- Automation execution history: 30 days.
- Security audit events: 90 days, configurable.
- AI conversations: configurable by user.

Administrator can change them. Never delete essential settings or active automation definitions through retention cleanup.

## 9. Secure website

Serve compiled Svelte assets via Rust; no separate production Node.js process. Require authenticated admin site, secure login, users/permissions, performance monitor, devices, integrations, AI configuration, diagnostics, automations, logs, backups, updates and settings. Use authenticated API/WebSockets, HTTPS with documented trust bootstrap (e.g. locally trusted CA or safe proxy). Never offer insecure HTTP authentication. Responsive desktop/tablet/mobile UI.

## 10. systemd deployment

Install native Rust binary as systemd service under dedicated unprivileged user. Configure auto-start, restart-on-failure, dependencies, health checks, config, resource limits, logs, graceful shutdown and controlled restart. Avoid Docker unless optional target is newer hardware. Use narrowly scoped privileged helpers for operations that truly require privileges. No general AI/root shell.

## 11. Backup system

Automate backups of SQLite DB, app and connector configuration, automations, rooms, device metadata, user settings, and encrypted secrets where appropriate. Support external disk or remote backup destination. Backups **on the same 256 GB drive do not protect from drive failure**; staging there is acceptable, but test restore from external storage. Show last successful backup and errors in dashboard.

## 12. AI performance

Default complex natural-language reasoning to an external AI provider. Use optional lightweight deterministic local parsing for well-defined commands. Keep permissions, device actions, schedules, connector I/O, state, network and event processing on the Mac mini. Validate CPU compatibility and benchmark any optional on-device LLM or STT/TTS before offering normal use. If AI API fails, normal web controls and automations continue.

## 13. Performance profiles

Three admin-selectable, safe profiles:

**ECO:** reduced noncritical metrics/polling/concurrency, optional voice off, minimal diagnostics.

**BALANCED (default):** normal monitoring, full connector operations, responsive dashboard, moderate background work.

**PERFORMANCE:** more frequent noncritical metrics, higher concurrency only where safe, more responsive optional services if supported.

Profiles must not reduce security, mute critical alerts or interrupt essential automations.

## 14. Dashboard hardware diagnostics

Add a Hardware page with model, CPU, RAM, disk type, capacity, SMART/health, network, OS, boot mode, CPU compatibility warnings and operating profile. If drive type cannot be determined, show **Unknown**. Include safe re-run diagnostics for admin.

## 15. Storage budget and final objective

256 GB is nominal capacity, not guaranteed available formatted space. Treat the following as **planning figures, not partitions or predictions**:

- OS/packages: 25 GB budget.
- App/integrations: 10 GB budget.
- DB/history: 20 GB budget.
- Logs/cache/temp: 5 GB budget.
- Optional local backup staging: 20 GB, not a safe backup destination.
- Remaining capacity: retain as free space and expansion, not allocated in advance.

Adapt the budget after inspecting drive format, actual capacity and observed use. Keep comfortable free space. No large local models by default.

Prioritize in this order:

1. Reliability.
2. Security.
3. Low CPU usage.
4. Responsive device commands.
5. Low RAM overhead.
6. Controlled disk writes.
7. Efficient network communication.
8. Maintainability.
9. Modular future expansion.

The core must be custom-built, lightweight, independent, and portable to newer Linux servers. Home Assistant may act **only as optional external interoperability connector**.

**First task:** Implement safe hardware diagnostics and a minimal Rust server foundation, then authenticated first-run admin setup, login, website, real hardware metrics, simulated device registry and WebSocket updates before adding full physical integrations.
