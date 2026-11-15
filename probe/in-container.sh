#!/bin/bash
# Runs INSIDE the debian:trixie container started by probe/build.sh.
# /stage holds config/ (the live-build overlay for the probe image).
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends \
  live-build debootstrap xorriso squashfs-tools mtools dosfstools \
  syslinux syslinux-common isolinux grub-pc-bin grub-efi-amd64-bin grub-common \
  ca-certificates cpio gnupg zstd

mkdir -p /build/lb /stage/out
cd /build/lb

# nomodeset keeps the plain firmware framebuffer: the Mac mini's NVIDIA graphics
# is the likeliest cause of a black screen. A second menu entry below turns the
# graphics drivers on, so the probe can also report how they behave.
APPEND="boot=live components hostname=jarvis-probe nomodeset console=tty0 console=ttyS0,115200n8"

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
  --iso-application "JARVIS Probe" \
  --iso-volume JARVIS_PROBE \
  --bootappend-live "$APPEND"

cp -a /stage/config/. config/
lb build

ISO=$(ls /build/lb/*.iso | head -n 1)

# ---- start by itself: boot the default entry after 5 seconds ------------------
# Debian live menus wait forever for a key; patch the finished ISO (the boot
# records are replayed unchanged) so an unattended computer starts the probe.
PATCH=/tmp/bootpatch
rm -rf "$PATCH"
mkdir -p "$PATCH"
xorriso -osirrox on -indev "$ISO" \
  -extract /isolinux/isolinux.cfg "$PATCH/isolinux.cfg" \
  -extract /isolinux/live.cfg "$PATCH/live.cfg" \
  -extract /boot/grub/config.cfg "$PATCH/config.cfg" \
  -extract /boot/grub/grub.cfg "$PATCH/grub.cfg"

sed -i -E 's/^([[:space:]]*)timeout[[:space:]]+[0-9]+/\1timeout 50/I' "$PATCH/isolinux.cfg"
grep -qiE '^[[:space:]]*timeout[[:space:]]+50' "$PATCH/isolinux.cfg" || printf 'timeout 50\n' >> "$PATCH/isolinux.cfg"
sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout=.*/\1set timeout=5/' "$PATCH/config.cfg" "$PATCH/grub.cfg"
grep -q 'set timeout=5' "$PATCH/config.cfg" || printf 'set timeout=5\n' >> "$PATCH/config.cfg"
grep -q 'set timeout=5' "$PATCH/grub.cfg" || sed -i '1i set timeout=5' "$PATCH/grub.cfg"

# Second entry: graphics drivers enabled (no nomodeset).
GFX="boot=live components hostname=jarvis-probe console=tty0 console=ttyS0,115200n8"
cat >> "$PATCH/live.cfg" <<EOF

label probe-graphics
	menu label Probe with ^graphics drivers enabled (if the first entry shows a blank screen)
	linux /live/vmlinuz
	initrd /live/initrd.img
	append $GFX
EOF
cat >> "$PATCH/grub.cfg" <<EOF

menuentry "Probe with graphics drivers enabled (if the first entry shows a blank screen)" {
	linux /live/vmlinuz $GFX
	initrd /live/initrd.img
}
EOF

xorriso -indev "$ISO" -outdev "$ISO.patched" \
  -boot_image any replay \
  -map "$PATCH/live.cfg" /isolinux/live.cfg \
  -map "$PATCH/isolinux.cfg" /isolinux/isolinux.cfg \
  -map "$PATCH/config.cfg" /boot/grub/config.cfg \
  -map "$PATCH/grub.cfg" /boot/grub/grub.cfg \
  -commit
mv "$ISO.patched" "$ISO"

cp "$ISO" /stage/out/jarvis-probe-amd64.iso
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" /stage
