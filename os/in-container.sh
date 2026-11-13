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
cp "$ISO" /stage/out/jarvis-os-amd64.iso
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" /stage
