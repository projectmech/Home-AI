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
APPEND="boot=live components hostname=jarvis nomodeset plymouth.enable=0 console=tty0 console=ttyS0,115200n8"
if [ "${SELFTEST:-0}" = "1" ]; then APPEND="$APPEND jarvis.selftest=1"; fi

lb config \
  --distribution trixie \
  --architectures amd64 \
  --linux-flavours amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --apt-recommends false \
  --firmware-chroot false \
  --firmware-binary false \
  --binary-images iso-hybrid \
  --debian-installer none \
  --memtest none \
  --win32-loader false \
  --iso-application "JARVIS OS" \
  --iso-volume JARVIS_OS \
  --bootappend-live "$APPEND"

cp -a /stage/config/. config/

# ---- the local AI model server: llama.cpp's llama-server, built for Sandy Bridge ----------
# Pinned to one commit. Built for the owner's real CPU, measured by JARVIS Probe: a
# Core i5-2415M (Sandy Bridge): SSE4.2, POPCNT and AVX yes; AVX2, FMA, F16C and BMI no.
# Built here, in debian:trixie (the same C library as the image), and copied in. The
# language MODEL is not in the image: `jarvis-model install` downloads it with a pinned
# hash (docs/AI.md).
LLAMA_COMMIT=b1b770d90d94cad9e9ea5b993bdbc383a522fb28
apt-get install -y --no-install-recommends build-essential cmake git
mkdir -p /build/llama
cd /build/llama
git init -q .
git remote add origin https://github.com/ggml-org/llama.cpp.git
git fetch -q --depth 1 origin "$LLAMA_COMMIT"
git checkout -q FETCH_HEAD
cmake -B build -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DLLAMA_CURL=OFF \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON \
  -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF -DGGML_LLAMAFILE=OFF -DGGML_AVX=ON -DGGML_AVX2=OFF \
  -DGGML_AVX512=OFF -DGGML_FMA=OFF -DGGML_F16C=OFF -DGGML_BMI2=OFF -DGGML_SSE42=ON \
  -DCMAKE_C_FLAGS="-march=sandybridge -mtune=sandybridge -O2" -DCMAKE_CXX_FLAGS="-march=sandybridge -mtune=sandybridge -O2"
cmake --build build -j"$(nproc)" --target llama-server
install -D -m 0755 build/bin/llama-server /build/lb/config/includes.chroot/usr/local/bin/llama-server
# The build fails if the binary contains an instruction Sandy Bridge lacks (AVX-512,
# FMA, F16C, AVX2 integer broadcasts and permutes, gathers).
objdump -d --no-show-raw-insn build/bin/llama-server > /tmp/llama.asm
BAD=$(grep -cE '%zmm[0-9]+|[[:space:]](vfmadd|vfnmadd|vfmsub|vfnmsub|vcvtph2ps|vcvtps2ph|vpbroadcast|vperm2i128|vpermd|vpermq|vpgather|vgather)[a-z0-9]*[[:space:]]' /tmp/llama.asm || true)
rm -f /tmp/llama.asm
[ "$BAD" = 0 ] || { echo "ERROR: llama-server contains $BAD instructions Sandy Bridge lacks" >&2; exit 1; }
cd /build/lb

lb build

ISO=$(ls /build/lb/*.iso | head -n 1)

# ---- the Mac mini's Ethernet driver must be in the image ---------------------
# The owner's machine (measured by JARVIS Probe): Macmini5,1 with a Broadcom BCM57765
# Gigabit Ethernet (14e4:16b4), driven by tg3. (An earlier guess, the 2010 model's
# NVIDIA forcedeth, is also kept: harmless.) Fail the build if tg3 is missing.
echo "network drivers present in the image:"
find /build/lb/chroot -path '*/drivers/net/ethernet/*' \( -name 'forcedeth.ko*' -o -name 'tg3.ko*' -o -name 'r8169.ko*' -o -name 'e1000e.ko*' -o -name 'igb.ko*' \) -printf '  %f\n' | sort -u
find /build/lb/chroot -name 'tg3.ko*' | grep -q . \
  || { echo "ERROR: tg3 (the Mac mini 5,1's Ethernet driver) is not in the image" >&2; exit 1; }

# ---- start by itself: boot the default entry after 5 seconds ------------------
# Debian live menus wait forever for a key (isolinux "timeout 0"; GRUB with no
# timeout), which is wrong for a headless server. A live-build hook for this
# did not run, so the finished ISO is patched instead: two small text files are
# replaced and the boot records (BIOS, EFI, hybrid MBR) are replayed unchanged.
PATCH=/tmp/bootpatch
rm -rf "$PATCH"; mkdir -p "$PATCH"
xorriso -osirrox on -indev "$ISO" \
  -extract /isolinux/isolinux.cfg "$PATCH/isolinux.cfg" \
  -extract /isolinux/live.cfg "$PATCH/live.cfg" \
  -extract /boot/grub/config.cfg "$PATCH/config.cfg" \
  -extract /boot/grub/grub.cfg "$PATCH/grub.cfg"

# isolinux (BIOS): 50 tenths of a second.
sed -i -E 's/^([[:space:]]*)timeout[[:space:]]+[0-9]+/\1timeout 50/I' "$PATCH/isolinux.cfg"
grep -qiE '^[[:space:]]*timeout[[:space:]]+50' "$PATCH/isolinux.cfg" || printf 'timeout 50\n' >> "$PATCH/isolinux.cfg"

# GRUB (EFI): timeout in seconds, set in config.cfg and, to be sure, at the top of grub.cfg.
sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout=.*/\1set timeout=5/' "$PATCH/config.cfg" "$PATCH/grub.cfg"
grep -q 'set timeout=5' "$PATCH/config.cfg" || printf 'set timeout=5\n' >> "$PATCH/config.cfg"
grep -q 'set timeout=5' "$PATCH/grub.cfg" || sed -i '1i set timeout=5' "$PATCH/grub.cfg"

# ---- two extra menu entries: Install and Recovery ----------------------------
# The default entry stays "Live system": nothing is ever installed or erased by
# just starting the medium. The installer runs only from its own entry.
APPEND_BASE="boot=live components hostname=jarvis nomodeset plymouth.enable=0 console=tty0"
cat >> "$PATCH/live.cfg" <<EOF

label jarvis-install
	menu label ^Install JARVIS OS (erases a disk you choose)
	linux /live/vmlinuz
	initrd /live/initrd.img
	append $APPEND_BASE jarvis.install=1

label jarvis-recovery
	menu label ^Recovery shell (root, installer medium only)
	linux /live/vmlinuz
	initrd /live/initrd.img
	append $APPEND_BASE jarvis.recover=1
EOF
cat >> "$PATCH/grub.cfg" <<EOF

menuentry "Install JARVIS OS (erases a disk you choose)" {
	linux /live/vmlinuz $APPEND_BASE jarvis.install=1
	initrd /live/initrd.img
}
menuentry "Recovery shell (root, installer medium only)" {
	linux /live/vmlinuz $APPEND_BASE jarvis.recover=1
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
echo "boot menu timeouts after patching:"
grep -iHE '^[[:space:]]*timeout' "$PATCH/isolinux.cfg" || true
grep -HE 'set timeout=' "$PATCH/config.cfg" "$PATCH/grub.cfg" || true

cp "$ISO" /stage/out/jarvis-os-amd64.iso
chown -R "${HOST_UID:-0}:${HOST_GID:-0}" /stage
