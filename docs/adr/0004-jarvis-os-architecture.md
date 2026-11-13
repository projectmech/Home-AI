# ADR 0004 — JARVIS OS: build strategy and first image

Date: 2026-11-13. Status: accepted for phases 1-2 (architecture and a minimal bootable image). Later phases are listed, not decided. Requirements: `prompts/07-JARVIS-OS.md`.

## Decisions

| Area | Decision | Why |
|---|---|---|
| Base | Debian 13 "trixie", amd64, Debian's own kernel (`linux-image-amd64`) | Requirement; no custom kernel. Debian's amd64 kernel and userland target the original x86-64 baseline, which a Core 2 Duo satisfies. *Not yet run on the real CPU.* |
| Image tooling | `live-build` producing a hybrid ISO (BIOS via syslinux, EFI via GRUB), built inside a `debian:trixie` container | Established Debian tooling; building in a trixie container makes the build independent of the host (GitHub's runners are Ubuntu). |
| Installer | Planned: Debian Installer with a preseed, plus JARVIS late-commands. **Not in this phase.** | Writing a new installer from scratch is the largest risk; d-i already does partitioning, LUKS2 and GRUB. LUKS2 defaults must be verified. |
| JARVIS inside the image | The signed release bundle (binary + dashboard) from GitHub, **verified with the same Sigstore check the installer uses**, then copied into `/opt/home-ai` | Reuses the tested artifact; the image build refuses an unverified or unsigned bundle. |
| Service | The same hardened `home-ai.service` as the server install, enabled at boot; data in `/var/lib/home-ai`; env in `/etc/home-ai/home-ai.env` | One definition for both install paths. |
| Accounts | No default account. `live-config`'s user creation is removed; no SSH server in this phase | Requirement: no known passwords. The live system is for testing; there is no interactive login on it yet. |
| Network | `systemd-networkd` with DHCP on wired interfaces; hostname `jarvis` | Minimal. `jarvis.local` (avahi) is not included yet. |
| Test | CI boots the ISO in QEMU with `-cpu Penryn` (a Core 2 model: SSE4.1, no SSE4.2, no AVX), once with BIOS and once with EFI (OVMF). A boot-time self-test unit, enabled only by the kernel parameter `jarvis.selftest=1`, checks the service over verified HTTPS and prints a PASS/FAIL line on the serial console | Proves the kernel, userland and our binary start on a Core 2-class CPU model, and that the bootloaders work, without any hardware. |

## The test ISO differs from a release ISO by one kernel parameter
CI bakes `jarvis.selftest=1` into the boot entry so the VM needs no keyboard. A release ISO is built without it. The self-test only runs when that parameter is present.

## What this phase does NOT show
- Anything on the real Macmini4,1: Apple firmware, its Ethernet and storage drivers, BIOS vs EFI behaviour.
- An installer, disk partitioning, LUKS2, Clevis/Tang, recovery, backups.
- That the ISO can be written to a USB stick and booted by the Mac mini. A stick test needs the real machine.
- QEMU's CPU model is a close approximation of the instruction set, not of the chip.

## Next phases (from prompts/07)
3 installer (d-i + preseed, UEFI/BIOS detection, LUKS2) → 4/5 install-time JARVIS integration and wizard → 7 Clevis/Tang with a separate Tang device, tested in VMs → 10 update infrastructure (see the signing conflict in prompts/07) → 12 real-hardware validation with the user's approval for any destructive step.

## Addendum 2026-11-13 — what the first runs taught
- Debian live images wait at their boot menu until a key is pressed; the VM test presses Enter through the QEMU monitor. A real appliance ISO will want a short auto-boot timeout, to be decided with the installer.
- A boot self-test must not write to a serial tty it does not own: the serial login prompt takes the port over and hangs up other holders. Use the kernel log (`/dev/kmsg`, with `kernel.printk_devkmsg=on`), which reaches every console.
- A self-test unit must not be `Type=oneshot` if it waits for boot to complete.
- Result: BIOS and EFI boot tests both pass under `-cpu Penryn` (run 43421607888). Still not evidence about the real Mac mini.
