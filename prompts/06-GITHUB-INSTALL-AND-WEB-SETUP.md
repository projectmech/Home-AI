# JARVIS — GITHUB INSTALLATION AND WEB-FIRST SETUP SYSTEM

> Added 2026-11-12. Mandatory additions. Consolidated from the user's message; requirements are preserved, wording is tightened. **Priority: implement this deployment and first-time setup experience before the smart-home integrations.** Prompt 03's hardware limits and docs/SECURITY.md still apply. See "Reconciliation" at the end.

## 1. Objective
Install and launch from the GitHub repository in a Linux terminal; do everything else in a secure web interface. The terminal must **not** be needed to configure: administrator accounts, AI providers, API keys, voice, wake word, personality and humor, Loxone, Apple Home, Denon/HEOS, Spotify, Yale, network monitoring, room assignments, automations, connector installation, server preferences.

## 2. Repository contents
README.md, CLAUDE.md, install.sh, uninstall.sh, update.sh, Cargo.toml, Rust core source, frontend source, systemd service templates, configuration templates, database migrations, connector modules, documentation, automated tests, GitHub Actions workflows. Scripts documented and executable. Users never build the frontend or compile Rust on the server.

## 3. Installation
```
git clone https://github.com/OWNER/REPOSITORY.git
cd REPOSITORY
sudo ./install.sh
```
Implemented **and tested**. The installer:
1. Detects the Linux distribution.
2. Verifies hardware compatibility.
3. Checks CPU architecture.
4. Verifies available RAM.
5. Checks available storage.
6. Detects SSD or HDD.
7. Verifies basic networking.
8. Checks required system dependencies.
9. Downloads a compatible release binary.
10. Verifies release integrity and authenticity.
11. Installs the Rust application.
12. Installs the compiled frontend.
13. Creates a dedicated service account.
14. Initializes configuration directories.
15. Prepares the SQLite database.
16. Configures the systemd service.
17. Configures the initial HTTPS listener.
18. Starts the backend.
19. Verifies server health.
20. Prints the web setup address and a one-time setup token.

Errors are handled safely with actionable diagnostics. No full compile on the Mac mini by default. GitHub Actions builds release binaries for the compatible x86-64 baseline (no AVX/AVX2). If no compatible binary exists, report it; do not start an expensive build.

## 4. Completion output
Something like:
```
Installation completed successfully.
Status: RUNNING
Web Dashboard:   https://192.168.1.100:8443
Initial Setup:   https://192.168.1.100:8443/setup
One-time Setup Token: [GENERATED SECURE TOKEN]
Open the setup URL in your browser.
```
Explain how to trust or verify the initial HTTPS certificate. Do not call the connection trusted until the certificate is validated. No default administrator with a known password.

## 5. First-time web setup wizard
First launch enters INITIAL SETUP MODE, only for creating the initial configuration, requiring the installer's one-time token. The token is: generated with secure randomness; time-limited; single use; invalidated after setup; rate-limited against guessing; not stored in plaintext; recoverable only through an authorized local administrative procedure. Arbitrary network users must not be able to claim an unconfigured server.

Steps:
1. **Welcome** — "Welcome to JARVIS. Your intelligent home management system. Let's configure your new home AI." Basic server information.
2. **Create administrator** — username, password, confirmation; optional passkey and MFA.
3. **Home configuration** — home name, country, timezone, language, temperature units, default room structure.
4. **AI provider** (optional at setup) — Anthropic, OpenAI, compatible external API, optional local provider; secure key entry; connection test; list compatible models.
5. **JARVIS voice** — enable, wake word, STT provider, TTS provider, voice, preview, expressiveness, accent, speed, language, humor level, listening behavior, microphone and output where supported. Voice testable from the page. Explain that browser microphone access needs permission and is not reliable always-on background listening.
6. **Home integrations** — Loxone, Apple Home interoperability, Home Assistant compatibility, Denon/HEOS, Spotify, Yale, network monitoring; each with its own web configuration: discovery, connection test, authentication, capability detection, health, error reporting; each asks only for what it needs.
7. **Device discovery** — list devices; rename, assign rooms, group, inspect capabilities, resolve duplicates.
8. **Security** — sessions, remote access preferences, authentication requirements, voice permissions, smart-lock permissions, administrative confirmation requirements, backup preferences.
9. **Finish** — summary (integrations, device count, AI status, voice, network, server health) and a Finish Setup button. On finish: invalidate the token, close the setup endpoints, enable normal authenticated operation, redirect to the dashboard.

## 6. Dashboard
Pages: Home, Rooms, Devices, Integrations, AI Assistant, Voice & Personality, Music, Network, Automations, Users, Server, Security, Settings. Real-time data. Server page: CPU, RAM, disk, uptime, network throughput, version, running services, connector health, AI provider status, logs, backups, update management. Restart supported components, change settings and troubleshoot connectors through authenticated web controls. No unrestricted root shell.

## 7. Startup and restarts
Native systemd service, enabled at install. After power loss: Linux boots → network → JARVIS starts → database loads → connectors reconnect → automations resume safely → dashboard available. No terminal interaction.

## 8. Updates through GitHub
Versioned releases. Dashboard Updates section: installed version, latest compatible stable version, release notes, compatibility, availability, status. An authorized administrator can start an update from the dashboard. The system: verifies the release source; downloads the correct binary; verifies integrity and authenticity; backs up; installs through a narrowly privileged updater; restarts safely; verifies health; rolls back on failure. No arbitrary remote scripts; the AI cannot update the system without administrator approval. Terminal recovery/update exists as a fallback.

## 9. Connector installation through the web
Integrations section: installed and available connectors, details, installation and permission requirements, install/remove, configuration forms, connection testing, logs. Trusted distribution mechanism; no arbitrary unverified uploads running with unrestricted permissions.

## 10. Performance
Mac mini Mid 2010, Core 2 Duo, 16 GB RAM, 256 GB (SSD/HDD unknown), Debian 13 minimal preferred. Native Rust core, compiled Svelte frontend, SQLite, WebSockets, systemd, external AI by default. Lightweight install; no Docker and no frontend toolchain on the production machine; build elsewhere, deploy binaries. The website stays responsive while integrations and automations run.

## 11. Recovery
Documented procedure for when the website is down. Terminal supports: service status, logs, restart, backup restoration, update rollback, recovery of initial administrator access, secure regeneration of setup credentials when appropriate. The setup wizard must not reopen after an ordinary service failure. Prevent unauthorized reinitialization of an existing installation.

## 12. Acceptance criteria
Repository can be cloned; install script succeeds on the supported Linux environment; compatible release binary installed; systemd service starts; health check succeeds; setup page opens; setup token required; administrator can be created; wizard completes; user can log in; dashboard works; configuration persists after restart; starts automatically after reboot; core device functions work with no browser connected; updates and backups manageable from the dashboard.

## Final requirement
The terminal is for initial installation and emergency recovery. The website is for everything else.

## Reconciliation with the current code and earlier decisions (Claude's notes, 2026-11-12)
- **TLS.** ADR 0001 chose plain HTTP on loopback behind a TLS proxy. §3.17 and §4 call for an HTTPS listener on the LAN at install time. This supersedes the ADR: the binary will terminate TLS itself (rustls) with a certificate generated at install, and the installer prints its fingerprint so the user can verify it. Needs a new ADR.
- **Setup token.** Today the server generates the token at startup, keeps it in memory, prints it to stdout, and it never expires. Required instead: issued by a local CLI command the installer calls, stored only as a hash with an expiry, rate-limited, and never regenerated by a mere restart.
- **Private repository.** The repository is currently private. `git clone` and release downloads on the Mac mini then need GitHub credentials on that machine. Either the repository becomes public or the installer needs an authenticated download path. **User decision.**
- **Authenticity.** "Verify integrity and authenticity" needs a signing scheme whose public key ships in the repository (candidates: minisign, or GitHub artifact attestations). Checksums alone prove integrity, not authenticity. To be decided in the ADR.
- **Wizard steps 4–7** configure subsystems that do not exist yet (AI, voice, connectors). They can only be real once those exist; until then the wizard shows them as "not available in this version" and never as working.
- **"Tested".** The installer can be tested in CI on a Debian container or VM. Boot, reboot survival and Core 2 Duo compatibility need the real Mac mini and stay NOT TESTED until then.
