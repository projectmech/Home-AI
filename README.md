# Home AI — Claude Code project starter pack

This is a **project context bundle**, not a working home AI application. It captures decisions, known hardware details, required integrations and first-pass acceptance criteria so Claude Code can build the real repository deliberately.

## Using the pack
1. Create an empty Git repository and copy this folder's contents into its root. Do not upload sensitive passwords, device pairing codes, or API tokens.
2. Read `CLAUDE.md` first. Review `docs/OPEN_QUESTIONS.md`; unknown information is intentionally marked unknown rather than assumed.
3. Start Claude Code **on a modern development machine**, not the 2010 Mac mini, to perform compilation, tests and packaging.
4. Tell Claude Code: *Read CLAUDE.md and docs/. Implement milestone M0, then M1 from docs/ROADMAP.md. Do not start physical connectors until the simulator and secure admin login are tested.*
5. Deploy only verified release builds to the Mac mini after testing the correct x86-64 CPU baseline, Linux boot/firmware, and secure TLS access.

## Precedence
`docs/PRD.md` defines product functionality. `docs/HARDWARE.md` defines known hardware constraints. `docs/SECURITY.md` defines non-negotiable security rules. `docs/ROADMAP.md` controls implementation sequence. Resolve conflicts explicitly in an architecture decision record (ADR).

## Documentation
- [Product requirements](docs/PRD.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Hardware](docs/HARDWARE.md)
- [Integrations](docs/INTEGRATIONS.md)
- [UI/UX](docs/UI_SPEC.md)
- [Security](docs/SECURITY.md)
- [Test criteria](docs/TEST_PLAN.md)
- [Development roadmap](docs/ROADMAP.md)
- [Unknowns](docs/OPEN_QUESTIONS.md)
- [Authoritative docs](docs/REFERENCES.md)

## Current state of the code (2026-11-12)
The first vertical slice is written: Rust core in `server/`, Svelte dashboard in `web/`. Lint, tests and the baseline release build pass in GitHub Actions. Nobody has run the dashboard against a live server yet, and nothing has run on the Mac mini; see the handoff record in `docs/ROADMAP.md`. Installing on a server: see `docs/INSTALL.md`. No release is published yet.

## Build and run (on a machine that can run locally compiled programs)
```
cd web && npm ci && npm run build && cd ..
cargo test --all
cargo run -- setup-token   # prints the one-time setup token
cargo run
```
The server listens on `http://127.0.0.1:8080` . Open that address, enter the token from `setup-token` (valid one hour, single use), create the administrator, sign in. Every device is a simulator. `cargo run -- hwdiag` prints a read-only hardware report. Settings: `APP_LISTEN`, `APP_DATA_DIR` (default `./data`), `APP_WEB_DIR` (default `./web/dist`), `APP_LOG_LEVEL`. For LAN access set `APP_TLS=self-signed` and a network `APP_LISTEN` such as `0.0.0.0:8443`; `home-ai tls-fingerprint` prints the certificate fingerprint to verify in the browser. Plain HTTP is refused on anything but loopback. See `docs/adr/0002-in-process-tls.md`.
