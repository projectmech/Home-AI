# Hardware and deployment profile

## Known (user-confirmed)
- Apple Mac mini 2010, Intel Core 2 Duo class.
- 16 GB DDR3 RAM.
- 256 GB storage capacity (drive type not confirmed).
- Intended 24/7 self-hosted operation with a secure browser-based login/dashboard.
- User is considering Ubuntu Server or another lightweight Linux. **Debian 13 minimal is a recommendation, not an installed fact.**

## Unknown — never invent
- Exact CPU revision, CPU instruction flags, drive model/health/SSD-vs-HDD, network topology/IPs, current OS/boot mode, whether native SSD and wired Ethernet are installed, physical location of development machine, server power/recovery preferences.

## Inventory commands to suggest (non-destructive)
Linux:
```
uname -a
lscpu
free -h
lsblk -d -o NAME,SIZE,MODEL,ROTA,TRAN
ip -br addr
systemctl --version
```
macOS:
```
system_profiler SPHardwareDataType SPSerialATADataType
```
Review results before selecting storage tuning or installation mode.

## Deployment plan
- Minimal supported Debian/Ubuntu, no desktop. Verify boot installer on actual Mac mini before touching disk. Back up first.
- Prefer Ethernet and DHCP reservation; private access only by default.
- Build on modern PC/Mac/CI; ship signed/verified native Rust release binary and precompiled static frontend.
- systemd under dedicated unprivileged account; secrets outside Git; secure HTTPS locally; off-device backup.
- Prevent heavy local LLM inference from starving the control engine.

## Storage / performance
- On SSD: scheduled TRIM only if supported; monitor drive health.
- On HDD: batch telemetry writes; reduce needless polling and seeks.
- SQLite transactional safety first; cap logs and history; keep free disk space.
- Live metrics every 5–15 s only while dashboard has clients (server-side background health checks continue), device health checks at sensible event-driven/low-frequency intervals.
- Goals, not claims: 150–300 MB idle core RSS; low idle CPU; benchmark CPU, RSS, disk I/O, action latency and restart recovery.
- Do not imply that same-drive copies are off-device backups.
