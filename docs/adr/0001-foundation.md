# ADR 0001 — Foundation for the first vertical slice

Date: 2026-11-12. Status: accepted for M0/M1; items marked *open* are not decided.

Precedence applied: `prompts/03` > `prompts/02` > `prompts/01`, then `docs/`.

## Decisions

| Area | Decision | Why |
|---|---|---|
| Shape | One Rust crate (`server/`, lib + bin `home-ai`) with modules `api`, `auth`, `db`, `devices`, `events`, `policy`, `metrics`, `hwdiag`, `ws`. Split into more crates only when a module needs its own dependency set. | Modular monolith, one binary, low overhead. |
| Runtime / HTTP | Tokio + Axum 0.8, tower-http for static files and headers. | Mature, async, small. |
| Storage | SQLite through `rusqlite` (bundled), one connection, WAL, `synchronous=FULL`, migrations by `PRAGMA user_version`. All calls go through `spawn_blocking`. | Durability is not traded for speed (prompt 03 §5). One connection is enough at this load; revisit with measurements. |
| Passwords | Argon2id (`argon2` crate defaults: m=19 MiB, t=2, p=1), minimum 12 characters. Hashing runs on the blocking pool. | Requirement. Cost on a Core 2 Duo is *unmeasured*; tune in M5. |
| Sessions | Opaque 256-bit random token in an `HttpOnly; Secure; SameSite=Strict` cookie, 12 h lifetime. Only the SHA-256 of the token is stored. New token on every login. | No session fixation; a leaked database holds no usable sessions. |
| CSRF | `SameSite=Strict` plus an `Origin` = `Host` check on every non-GET API request. WebSocket upgrades *require* a matching `Origin`. | Browsers do not apply CORS to WebSockets. |
| First run | A single-use setup token is generated while the `users` table is empty and printed to the server console. `/api/setup` needs it and creates the admin atomically; afterwards setup is closed, including across restarts. | No default password; setup limited to whoever can read the server console. |
| Login rate limit | Five failures in five minutes lock that username for 60 s; in memory, bounded table. | Temporary, so it cannot lock the admin out for good. Keyed by username only, so someone on the LAN can delay a login; add per-source limits once the proxy passes a trusted client address. |
| Roles and policy | `admin`, `standard`, `restricted`. Every command is a typed `Action`, validated against the device kind and value ranges, then evaluated: restricted = read only; unlock = admin only **and** password re-entry (step-up). | AI proposals (M4) will go through the same function. |
| Events | Tokio broadcast channel, capacity 256, monotonically increasing `seq`. A lagging WebSocket client gets a full snapshot instead of a backlog. | Bounded memory; correct state after reconnect. |
| Metrics | `sysinfo`. Sampled every 10 s **only while a dashboard socket is open**. Unmeasurable values are `null` in the API and "Not available"/"Unknown" in the UI. | Low idle CPU; no fabricated metrics. |
| Frontend | Svelte 5 + TypeScript + Vite, built to `web/dist`, served by the Rust binary from `APP_WEB_DIR`. No Node.js in production. | Requirement. |
| CPU baseline | `.cargo/config.toml` sets `target-cpu=x86-64` for Linux targets. | Core 2 Duo has no AVX. Needs a real Mac mini smoke test (A08). |
| TLS | The binary speaks plain HTTP and **refuses to bind a non-loopback address**. LAN access goes through a TLS-terminating reverse proxy on the same host (candidate: Caddy with its internal CA; clients install the root certificate). | Login can never be served in plaintext on the network by misconfiguration. In-process TLS (rustls) would remove the extra service; *open*, decide in M5 with measurements. |

## Known limits of this slice

- The `Connector` trait is synchronous, which suits the in-process simulator only. Network connectors (M2) need an async trait with deadlines and a per-connector task.
- No user-management API or UI yet; `api::create_user` exists for tests.
- No MFA/passkeys, no backups, no update mechanism, no systemd unit.
- SMART data is not collected. Drive type comes from `/sys/block/*/queue/rotational` on Linux and is "Unknown" elsewhere.
- The setup token is printed to stdout; under systemd that lands in the journal. It is single use and worthless after setup.

## Still open (from docs/ARCHITECTURE.md)

Connector isolation mechanism, retention/rollups, OS boot mode on Macmini4,1, backup/rollback, voice, Apple Home architecture, router integration.
