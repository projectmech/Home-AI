# JARVIS OS installer

Installs JARVIS OS from the ISO onto a computer's internal disk with an
encrypted root. Written for the 2010 Mac mini but not specific to it.

**Status:** proven in virtual machines only (BIOS and EFI, CI run 43447437696).
Never run on the real Macmini4,1. See "Not proven" below.

## How to start it
Boot the ISO. The default entry is still the live test image: nothing is ever
installed or erased by simply starting the medium. Pick
**Install JARVIS OS (erases a disk you choose)** from the boot menu. The menu
also has **Recovery shell (root, installer medium only)**, which exists only on
the installer medium and is not part of an installed system.

## What it asks, and what it does
1. Detects the boot mode (EFI or legacy BIOS) and installs the same way, because
   the installed system must start the same way.
2. Lists internal disks of at least 8 GiB (not the installer medium) with model,
   SSD or hard disk, and SMART health.
3. You type `ERASE <disk>` exactly. Anything else stops.
4. You choose a passphrase (at least 12 characters). A 32-character recovery
   key is generated, shown once, and you must type it back. Write it down: it is
   not stored anywhere in readable form.
5. Partitions: EFI = GPT with an EFI system partition, `/boot` and the encrypted
   root; BIOS = MBR with `/boot` and the encrypted root.
6. LUKS2 on the root. The passphrase and the recovery key are two separate
   keyslots, so either unlocks the disk and either can be removed later.
7. Copies the system from the ISO, builds the initramfs, installs GRUB, runs a
   final check (kernel, initramfs, grub.cfg root, crypttab, JARVIS core present).
8. `/boot` is not encrypted (it holds only the kernel, initramfs and GRUB). The
   data, including the JARVIS database and TLS key, is on the encrypted root.

At every start the installed system asks for the passphrase on the console
before it boots. There is no remote unlock and no SSH. Unattended unlock
(Clevis/Tang) needs a separate Tang device and is not built.

## Test-only mode
`jarvis.install=auto` with `jarvis.install.disk=`, `jarvis.install.erase=` and
`jarvis.install.pass=` on the kernel command line runs the installer without
prompts. It is used only by `os/test-install.sh`. Anyone who can edit the boot
command line can already read the medium, so it adds no access, but do not use it
for a real install: the passphrase would be visible on the command line.

## What CI proves (os/test-install.sh, matrix bios/efi)
Installs onto an empty virtual disk under a Core 2 CPU model, then boots the
installed disk with the real boot loader, unlocks it (BIOS: passphrase; EFI:
recovery key on the second boot), checks the console box and that the served
certificate matches its fingerprint, creates the administrator with the setup
token, powers off, boots again, unlocks, and checks that the certificate is
unchanged, setup stays closed and the administrator can sign in.

## Not proven
- Any real hardware: the Mac mini's firmware, its boot picker, its disk, GRUB
  on its EFI/BIOS-compat mode, the text console with `nomodeset`.
- Wrong passphrase handling, interrupted install, a disk with existing data
  other than empty, two internal disks.
- Wi-Fi (not in the image), voice, AI, connectors, signed ISO, Tang.
- A real install over the existing Ubuntu Server: destructive, needs explicit
  approval at the time, after the live image has been seen working on the Mac.

## The guided setup screens (added 2026-11-15)
Choosing **Install JARVIS OS** from the boot menu now opens a full-screen guided setup
(`jarvis-setup`, built on whiptail, cyan on black like the boot screen) instead of plain
prompts. One question per screen, **Back** always works, and nothing is changed until the
last screen:

1. **Keyboard**: US, British, Norwegian, Swedish, Danish, Finnish, German, French,
   Spanish, Italian (applied at once, and saved for the installed system).
2. **Network**: use the Ethernet cable, or **connect to Wi-Fi** (scans for networks,
   asks for the password, connects, shows the address), or skip. A Wi-Fi network joined
   here stays joined after installation (only the derived key is kept, never the password).
3. **Disk**: lists the internal disks with size, model and SSD/hard-disk, shows what is on
   the chosen disk now, warns about a spinning disk, then **partitions**: the whole disk
   (recommended) or a system partition of a size you choose (the rest stays empty).
   The layout is always a small EFI area, a 1 GB /boot, and one encrypted (LUKS2) system
   partition.
4. **Your account**: user name, computer name, password (8+ characters) and the disk
   passphrase (12+ characters; the same as the password, or separate). The account is an
   administrator (sudo); the root account is locked.
5. **Review**, then type `ERASE`, then the one-time **recovery key** (write it down, type it
   back), then the installation runs.

`jarvis-install` still does the work and still refuses to touch a disk without the typed
confirmation. The automated test mode (`jarvis.install=auto`) now also takes
`jarvis.install.user`, `.userpass`, `.hostname` and `.keymap`, so CI proves the account is
created with a password, root is locked, the computer name is set and the home directory
exists. **Not proven:** the screens themselves have been checked by reading, not by a
person using them; the first run on the real machine will show what needs polishing.
Known limit: the disk-unlock prompt at start-up may use a US keyboard layout, which is why
the setup advises letters and digits and always offers the recovery key.

## No Ethernet? (the owner's room has none)
- Choose **Wi-Fi** in step 2 of the setup (it is the default when no cable is found). The
  Mac mini's Broadcom BCM4331 uses the proprietary `wl` driver built into the image; CI
  records that the module matches the image kernel, knows the chip (14e4:4331) and has its
  dependencies. It has **not** been seen working on the real chip yet. If no Wi-Fi adapter
  appears, the setup shows the last kernel messages about it: send those.
- The language model normally downloads over the network (`sudo jarvis-model install`).
  Without a network: download the file named in `jarvis-model` on another computer, copy it
  to a USB stick as `model.gguf`, plug the stick in and run `sudo jarvis-model install-usb`.
  The file is checked against the same pinned SHA-256 first.
