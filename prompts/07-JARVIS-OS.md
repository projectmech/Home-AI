# JARVIS OS — a dedicated Debian-based operating system image

> Added 2026-11-13. Consolidated from the user's message; requirements are preserved, wording is tightened. It builds on prompts 01-06 and does not discard any earlier functionality. Where it conflicts with an earlier decision, see "Reconciliation" at the end. Hardware limits from prompt 03 still apply.

## 1. Objective
A real, installable OS named **JARVIS OS**: Debian GNU/Linux (13), lightweight, headless, hardened, running 24/7 as a home-automation and AI appliance. Once installed the machine becomes a dedicated JARVIS server; the web dashboard is the primary interface; the terminal stays for recovery, advanced administration and development. Not a script that installs onto an existing OS. Do not write a kernel; use Debian's maintained kernel and tooling.

Properties: lightweight, headless, secure by design, encrypted automatic startup, authenticated updates from GitHub, browser-configured, extensible connectors.

## 2. Target hardware
Mac mini Mid 2010 (Macmini4,1, to be verified), Core 2 Duo, 16 GB DDR3, 256 GB (type unknown), x86-64, Gigabit Ethernet. Avoid: large services, heavy runtimes, desktop environments, mandatory containers, polling, large local AI models, hardware-acceleration requirements, AVX/AVX2 or newer instructions. Compile custom native code for a baseline x86-64 compatible with the CPU; verify real CPU capabilities first.

## 3. Build system
Reproducible, Linux-based, preferably on Debian 13 amd64. Evaluate live-build, Debian Installer, debootstrap, initramfs-tools, GRUB, Debian packaging, systemd, apt, ISO utilities; choose a maintainable approach. Developer flow: `git clone …/jarvis-os.git && cd jarvis-os && ./build.sh` produces an image (OWNER is a placeholder; do not assume the repository exists). Suggested layout: CLAUDE.md README.md LICENSE Makefile build.sh config/ installer/ packages/ kernel/ initramfs/ boot/ services/ core/ web/ connectors/ security/ updater/ recovery/ tests/ scripts/ docs/ .github/workflows/ — adjust where justified.

## 4. Image
Bootable installable ISO `jarvis-os-amd64.iso` containing: kernel, minimal Debian userspace, bootloader, installer, firmware, network support, storage-encryption tools, the JARVIS Rust core and web dashboard, configuration and systemd units, first-time setup service, connector framework, secure update client, recovery utilities, diagnostics. A tested core and dashboard ship inside the image; no download of the application after installing the OS.

## 5. Legacy Mac mini boot
Consider legacy BIOS/CSM, EFI where compatible, GPT, GRUB, bootable USB, recovery media, bootloader recovery. Investigate and test which modes work on the real machine; do not assume. The installer detects boot mode and offers a fallback. No experimental boot configuration by default.

## 6. Installer
Text-based or lightweight. Hardware detection; disk selection; disk health; capacity check; boot-compatibility check; encryption configuration; recovery passphrase; network configuration; OS install; JARVIS core install; bootloader; service configuration; first-start verification. Warn that installation may erase data and require explicit confirmation before touching partitions. Never erase automatically. Support the 256 GB disk. Finish by showing the address of the web setup wizard.

## 7. Encrypted storage
LUKS2 (dm-crypt, cryptsetup) with a suitable filesystem, protecting the root filesystem where practical, JARVIS configuration, device credentials, AI keys, databases, user data, logs, automations, persistent data. No proprietary crypto. Keep an independent recovery passphrase; never store it or a plaintext disk key on the machine. Document limits of unencrypted early-boot components.

## 8. Network-bound unlock
Clevis + Tang + clevis-initramfs + LUKS2, with recovery procedures. Tang runs on a **separate trusted device**, never on the encrypted machine. Scenarios: (A) Tang configured at install; (B) Tang configured later through authenticated administration — boot with the recovery passphrase first, then enroll Tang under controlled steps. Verify the binding, early-boot network and initramfs before relying on automatic startup. Never remove the last working recovery keyslot. Boot flow: power on → kernel+initramfs → early network → contact Tang → unlock LUKS2 root → Debian startup → JARVIS core → dashboard → integrations → automations resume safely. If Tang is unavailable the disk stays encrypted and recovery options appear. Do not bypass encryption. Tang reachability is not hardware identity.

## 9. Core, dashboard, voice, connectors
- **Rust core** (modular monolith, no Node.js in the production backend): device registry, connector manager, AI orchestration, automation engine, event bus, authentication, authorization, API and WebSocket servers, network and system monitoring, notifications, voice sessions, configuration, update coordination, audit log. Runs as an unprivileged systemd service; narrow privileged helpers only where necessary.
- **Voice** as defined in prompt 05 (wake word "Jarvis", expressive TTS, interruption, follow-up listening, English and Norwegian, humor level, memory), optional and resource-limited, with room satellites.
- **Connectors**: Loxone, Apple Home interoperability, Denon/HEOS, Spotify, Yale, Home Assistant compatibility, network monitoring — each with configuration, authentication, discovery, capabilities, control, real-time state, health, errors, secure credential storage. Home Assistant is never the core. Later connectors installable.

## 10. Web-first setup and dashboard
After install, open the wizard, e.g. `https://jarvis.local` (with an IP-address alternative). Valid HTTPS with documented initial trust; never fall back to plaintext. Svelte + TypeScript, served by the Rust backend. Pages: Home, Rooms, Devices, Integrations, AI Assistant, Voice & Personality, Music, Network, Automations, Security, Server, Updates, Users, Settings. Server page: CPU, RAM, disk, uptime, kernel version, JARVIS OS version, core version, service health, temperature, network throughput, logs, available updates, backup health. Responsive; few animations. Configuration through the website except tasks that need early-boot access or recovery.

## 11. Security
Zero-trust: LUKS2, HTTPS, Argon2id, optional passkeys and MFA, RBAC, connector isolation, encrypted credential storage, verified updates, firewall, hardened units, protected admin APIs, audit logs, backup encryption, SSH key authentication, recovery procedures. Keep the repository private where proprietary access is needed; respect open-source licenses; no claim that binaries cannot be extracted from a running machine; no security through obscurity; no invented cryptography.

## 12. JARVIS Release Signing (JRS) — see Reconciliation
Ed25519 via established Rust libraries: sign OS images and update packages; verify integrity; trusted public keys; key rotation; release manifests; version verification; anti-rollback; release history. Private keys never on production servers. The installer verifies release artifacts before installing. JRS must not replace or weaken Debian's own package signature checks.

## 13. Updates
Layer A — OS (kernel, Debian packages, security fixes, services, boot components) via authenticated Debian repositories. Layer B — JARVIS software (core, dashboard, connectors, voice, AI orchestration, automations) via signed releases. Do not assume the layers have the same rollback ability; separate health checks and recovery; no unverified code from GitHub. Web updater shows: current version, available updates, notes, security status, signature status, progress, restart needs, history, rollback availability. Before updating: verify, check compatibility and disk space, back up, stage, validate integrity, install with a restricted updater, restart services, health-check, roll back where supported. Kernel and bootloader changes need a separate tested recovery path. Never promise atomic rollback of all OS changes unless implemented and tested.

## 14. Performance, monitoring, network, backups
Minimal idle CPU and memory, fast startup, few background processes, static frontend, external AI by default, optional lightweight local voice/AI only if benchmarks support it, performance profiles. Native monitoring of CPU, RAM, disk, interfaces, services, temperature, filesystem, database, connectors, AI connectivity, and network-unlock health after boot; bounded retention. Network configuration in the wizard: hostname, DHCP or static IP, DNS, gateway, status, connectivity test, local name discovery; no silent changes; never silently disconnect the only administrator; recovery for bad settings. Encrypted backups of database, configuration, connector settings, rooms, automations, user settings, relevant system config and secrets to separate storage; a recovery image; procedures for failed boot, damaged config, failed update, lost network, unavailable Tang, database corruption, recovery-passphrase unlock, restoring configuration; document LUKS header backup and recovery; no unprotected recovery material on the machine.

## 15. Build pipeline and tests
Pipeline: download verified Debian packages, pinned dependency resolution, build core, build frontend, assemble packages, include systemd units, generate installer parts, generate ISO, validate it, checksums, release metadata, sign, publish. Build on a newer Linux machine or GitHub Actions; the Mac mini never compiles the OS. Protect signing credentials from untrusted pull requests; document non-reproducible inputs. Test in virtual machines: ISO boot, installation, partitioning, encryption, unlock, network configuration, systemd startup, web setup, login, dashboard, connectors, app updates, OS updates, backup restore, recovery; BIOS and EFI. Validate on the real Macmini4,1 before calling it production-ready. No destructive tests on physical disks without explicit approval.

## 16. Phases
1 architecture · 2 minimal bootable image · 3 installer (disk selection, partitioning, encryption, bootloader) · 4 core integration · 5 web setup · 6 server dashboard · 7 encryption and network unlock · 8 connectors and AI · 9 voice and personality · 10 update infrastructure · 11 performance · 12 production validation.

## 17. Acceptance
Bootable ISO generated; boots in a supported VM; installer installs; bootloader works; no desktop; JARVIS starts automatically; web setup reachable; administrator can be created; dashboard works; simulation works; authentication enforced; LUKS2 works; Tang unattended unlock demonstrated in a test environment; recovery unlock works; core restart recovery works; signed update verification works; performance measured; a real-hardware validation plan exists; installation and recovery documentation complete. Hardware-dependent items are not production-ready until physically tested. Blocked steps are documented and independent work continues. Do not stop at documentation.

---

## Reconciliation with existing decisions (Claude's notes, 2026-11-13; confirm with the user)
1. **Signing — conflict, needs a decision.** On 2026-11-12 the user asked for Sigstore keyless signing and *no permanent private signing key unless absolutely necessary*; releases are signed that way today (ADR 0003). JRS now asks for Ed25519 with managed keys, rotation and anti-rollback. Not silently resolved. Proposal: keep Sigstore keyless as the signing and provenance mechanism for OS images and application releases; add the parts keyless does not give by itself (a signed release manifest with a monotonic version, anti-rollback check, release history) on top of it. An Ed25519 key would be introduced only if the user decides the keyless trust (GitHub account/OIDC + Sigstore public services) is not acceptable for OS images.
2. **Repository.** The structure suggests a new `jarvis-os` repository. To reuse the tested core, dashboard, installer and signing without duplication, the OS build lives in this repository under `os/`. A split can happen later. The repository stays private, so ISO downloads need GitHub sign-in.
3. **Installer.** Writing a custom installer from scratch is the largest risk in this plan. Proposal: Debian Installer with a preseed and late-commands, adding JARVIS-specific steps, rather than a new installer. LUKS2 defaults in the installer's guided mode need to be verified, not assumed.
4. **The Mac mini currently runs Ubuntu Server** (installed by the user). Installing JARVIS OS erases it. That needs the user's explicit approval at the time, and a bootable-USB test of the Mac mini's firmware first. The interim install path (`get.sh`, USB kit) keeps working meanwhile.
5. **Tang** needs a separate always-on device on the home network. None exists yet; it does not block earlier phases.
6. **`https://jarvis.local`** needs mDNS on the server (avahi) and certificate names that match; client support for `.local` varies (Windows and some Android versions), so the IP address stays the documented fallback. The certificate remains self-signed until the user installs it or checks its fingerprint.
7. **Debian vs Ubuntu.** The OS is Debian 13 as specified; the current Ubuntu install and tests are not evidence about Debian 13 on this hardware.
8. **Firmware.** A minimal image omits non-free firmware and CPU microcode by default; whether the Mac mini needs any must be established on the hardware.
