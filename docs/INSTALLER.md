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
