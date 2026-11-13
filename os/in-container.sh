#!/bin/bash
# Runs INSIDE the debian:trixie container started by os/build.sh.
# /stage holds config/ (live-build overlay with the JARVIS files already placed).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  live-build debootstrap xorriso squashfs-tools mtools dosfstools \
  syslinux syslinux-common isolinux grub-pc-bin grub-efi-amd64-bin grub-common \
  ca-certificates cpio gnupg zstd

mkdir -p /build/lb /stage/out
cd /build/lb

# console=ttyS0 comes last so /dev/console is the serial port in a VM.
# nomodeset: keep the plain firmware framebuffer for the text console; the
# 2010 Mac mini's NVIDIA graphics is not needed on a headless server and a
# native-mode graphics driver is the most likely cause of a black screen.
APPEND="boot=live components hostname=jarvis nomodeset console=tty0 console=ttyS0,115200n8"
if [ "${SELFTEST:-0}" = "1" ]; then APPEND="$APPEND jarvis.selftest=1"; fi

lb config \
  --distribution trixie \
  --architectures amd64 \
  --linux-flavours amd64 \
  --archive-areas main \
  --apt-recommends false \
  --binary-images iso-hybrid \
  --debian-installer none \
  --memtest none \
  --win32-loader false \
  --iso-application "JARVIS OS" \
  --iso-volume JARVIS_OS \
  --bootappend-live "$APPEND"

cp -a /stage/config/. config/
lb build

ISO=$(ls /build/lb/*.iso | head -n 1)

# ---- the Mac mini's Ethernet driver must be in the image ---------------------
# Macmini4,1: NVIDIA MCP89 Ethernet (PCI 10de:0d7d), driven by forcedeth, which
# needs no firmware. Fail the build if the module is missing from the image.
echo "network drivers present in the image:"
find /build/lb/chroot -path '*/drivers/net/ethernet/*' \( -name 'forcedeth.ko*' -o -name 'tg3.ko*' -o -name 'r8169.ko*' -o -name 'e1000e.ko*' -o -name 'igb.ko*' \) -printf '  %f\n' | sort -u
find /build/lb/chroot -name 'forcedeth.ko*' | grep -q . \
  || { echo "ERROR: forcedeth (the Mac mini's Ethernet driver) is not in the image" >&2; exit 1; }

# ---- start by itself: boot the default entry after 5 seconds ------------------
# Debian live menus wait forever for a key (isolinux "timeout 0"; GRUB with no
# timeout), which is wrong for a headless server. A live-build hook for this
# did not run, so the finished ISO is patched instead: two small text files are
# replaced and the boot records (BIOS, EFI, hybrid MBR) are replayed unchanged.
PATCH=/tmp/bootpatch
rm -rf "$PATCH"; mkdir -p "$PATCH"
xorriso -osirrox on -indev "$ISO" \
  -extract /isolinux/isolinux.cfg "$PATCH/isolinux.cfg" \
  -extract /boot/grub/config.cfg "$PATCH/config.cfg" \
  -extract /boot/grub/grub.cfg "$PATCH/grub.cfg"

# isolinux (BIOS): 50 tenths of a second.
sed -i -E 's/^([[:space:]]*)timeout[[:space:]]+[0-9]+/\1timeout 50/I' "$PATCH/isolinux.cfg"
grep -qiE '^[[:space:]]*timeout[[:space:]]+50' "$PATCH/isolinux.cfg" || printf 'timeout 50\n' >> "$PATCH/isolinux.cfg"

# GRUB (EFI): timeout in seconds, set in config.cfg and, to be sure, at the top of grub.cfg.
sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout=.*/\1set timeout=5/' "$PATCH/config.cfg" "$PATCH/grub.cfg"
grep -q 'set timeout=5' "$PATCH/config.cfg" || printf 'set timeout=5\n' >> "$PATCH/config.cfg"
grep -q 'set timeout=5' "$PATCH/grub.cfg" || sed -i '1i set timeout=5' "$PATCH/grub.cfg"

xorriso -indev "$ISO" -outdev "$ISO.patched" \
  -boot_image any replay \
  -map "$PATCH/isolinux.cfg" /isolinux/isolinux.cfg \
  -map "$PATCH/config.cfg" /boot/grub/config.cfg \
  -map "$PATCH/grub.cfg" /boot/grub/grub.cfg \
  -commit
mv "$ISO.patched" "$ISO"
echo "boot menu timeouts after patching:"
grep -iHE '^[[:space:]]*timeout' "$PATCH/isolinux.cfg" || true
grep -HE 'set timeout=' "$PATCH/config.cfg" "$PATCH/grub.cfg" || true

cp "$ISO" /stage/out/jarvis-os-amd64.iso
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" /stage
