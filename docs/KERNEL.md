# The JARVIS kernel

The owner asked for "my own kernel with my own drivers" and to keep the boot animation.
This is a Linux kernel **built from the signed kernel.org source** with a configuration
written for the measured hardware (docs/HARDWARE.md), packaged as Debian packages.

## What "own drivers" means here
The kernel carries the drivers this Mac mini 5,1 needs and leaves out what it does not
(AMD/NVIDIA graphics, FireWire, Thunderbolt, PCMCIA, hibernation, most other hardware).
It does **not** contain newly written drivers: the Broadcom Wi-Fi chip is still served by
Broadcom's `wl` driver (built against this kernel by the image build) or the in-tree
`b43` (needs Broadcom firmware, 2.4 GHz only here). Writing a Wi-Fi driver from scratch is
not a realistic task.

## Contents (kernel/jarvis.config over x86_64_defconfig)
- **Boot animation:** UEFI stub, EFI framebuffer, simpledrm, **Intel HD 3000 (i915) built
  in** with fbdev emulation and the framebuffer console, plus QEMU graphics for CI. The
  Plymouth theme itself is unchanged (it lives in the initramfs); the kernel gives it a
  display driver from the first moment.
- **Network:** tg3 Ethernet built in; cfg80211/mac80211/lib80211 and b43 as modules;
  USB tethering and USB Ethernet drivers (Android RNDIS/NCM, iPhone, RTL8152) for a room
  without Ethernet.
- **Disk and live image:** AHCI/SATA, NVMe, SCSI disk and CD, squashfs (xz, zstd),
  overlayfs, loop, ISO 9660, ext4, vfat, exFAT, dm-crypt with AES-NI.
- **Machine:** Apple keyboard and IR, Bluetooth (BCM20702), Cirrus CS4206 and HDMI audio,
  USB audio, applesmc and coretemp sensors, iTCO watchdog, intel_pstate.
- **Hardening:** KASLR, strong stack protector, strict RWX, hardened usercopy, fortify,
  init-on-alloc, slab hardening, page-table isolation, retpoline, strict devmem.
- Kernel release: `<6.12.y>-jarvis-amd64` (the suffix lets the image builder find it).

## Build and checks
`kernel/build.sh` (docker) or the **Kernel** workflow: picks the newest 6.12 long-term
kernel, verifies kernel.org's **signed** `sha256sums.asc` and then the tarball, merges the
config, fails if any option in `kernel/required.txt` did not end up set, reports options
that dependency resolution dropped, and builds `linux-image`, `linux-headers` and
`linux-libc-dev`.

## In the OS image
`os/build.sh --kernel-debs DIR` installs these packages, then `os/kernel-hook/0150-...`
removes Debian's kernel and rebuilds the initramfs (after the boot screen theme is in
place); the Wi-Fi hook builds `wl` against the JARVIS headers. The **OS image (JARVIS
kernel)** workflow builds that image next to the normal one, checks that only the JARVIS
kernel is present, and runs the BIOS and EFI boot tests and the three encrypted installs
including the boot-screen one. The normal image (Debian's kernel) stays the default until
this one is proven.

## Costs and limits (be honest)
- **Security updates are now yours.** Debian patches its kernel for you; this one needs a
  rebuild when kernel.org publishes a fix. The workflow always takes the newest 6.12.
- **Not yet shown on the real machine.** CI proves it boots and installs in virtual
  machines. The i915 boot animation, Wi-Fi, sound, sensors and Bluetooth need the Mac mini.
- No module signing / Secure Boot (the machine has no Secure Boot).
