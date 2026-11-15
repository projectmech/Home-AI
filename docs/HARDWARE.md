# Hardware and deployment profile

## Measured on 2026-11-15 (JARVIS Probe report from the real machine)
This **replaces the assumptions below** where they differ. Source: `jarvis-probe` run in UEFI mode on the owner's Mac mini (redacted report; the raw report is not committed).

| Part | Measured |
|---|---|
| Model | **Mac mini 5,1 (mid-2011, A1347)**, Apple EFI 135.0.0.0.0 (2019), **UEFI 64-bit**, no Secure Boot, boots from the Option-key picker |
| CPU | **Intel Core i5-2415M (Sandy Bridge)**, 2 cores / 4 threads, 2.3 GHz (turbo 2.9). Has SSE4.1, SSE4.2, POPCNT, AES-NI, **AVX**; no AVX2, FMA or F16C |
| Memory | 2 × 8 GB DDR3-1600 SODIMM = 15.9 GB usable |
| Disk | TOSHIBA MK5065GSXF, **500 GB, 5400 rpm hard disk** (not an SSD), SATA 3 Gb/s. SMART "PASSED" but worn: 34,913 power-on hours, Load_Cycle_Count at its rated limit (normalised value 1), 13 % life left on power-on hours. Existing layout: 1 GB EFI, 2 GB ext4, 462.7 GB LVM (an Ubuntu Server install) |
| Ethernet | Broadcom **BCM57765** Gigabit (14e4:16b4), kernel driver **tg3** (works in the stock Debian kernel). No cable was connected during the probe |
| Wi-Fi | Broadcom **BCM4331** 802.11a/b/g/n (14e4:4331), Apple AirPort Extreme. In the stock kernel `b43` binds but needs firmware that is not in Debian main; with b43's HT-PHY support only the 2.4 GHz band is available. The proprietary `wl` driver (broadcom-sta, non-free) covers 2.4 and 5 GHz |
| Bluetooth | Broadcom BCM20702 (btusb loads) |
| Graphics | Intel HD Graphics 3000 (i915) — **not NVIDIA**; the probe ran with `nomodeset` (EFI framebuffer 1920x1080) |
| Audio | Intel HDA with Cirrus CS4206 codec: analog out and analog line-in, optical/SPDIF in and out, headphone jack sensing. **No built-in microphone.** HDMI audio needs kernel modesetting (absent with `nomodeset`) |
| Other | Apple IR receiver, FireWire 800 (TI XIO2213), Thunderbolt 1, SD card reader (on the Ethernet chip), applesmc fan/temperature sensors |

Consequences recorded elsewhere: the "Core 2 Duo, no AVX" baseline in CLAUDE.md and the Core 2 CI tests were written for a wrong guess; they remain safe (a Core 2-compatible build also runs here) but leave performance on the table. The language-model server can use AVX on this CPU. The installer's NVIDIA `forcedeth` assumption is wrong for this model; `tg3` is what matters. A 2.5" SATA SSD is the single most useful upgrade (the current disk is at the end of its rated life).


## Known (user-confirmed)
- Apple Mac mini (the owner first said "2010, Core 2 Duo"; the probe measured a mid-2011 Macmini5,1 with a Core i5-2415M: see the table above).
- 16 GB DDR3 RAM.
- 256 GB storage capacity (drive type not confirmed).
- Intended 24/7 self-hosted operation with a secure browser-based login/dashboard.
- User is considering Ubuntu Server or another lightweight Linux. **Debian 13 minimal is a recommendation, not an installed fact.**

## Unknown — never invent
- Network topology/IPs, whether the Ethernet cable is connected where the server will live, physical location of development machine, server power/recovery preferences.

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
