#!/usr/bin/env bash
# Black-box test of the JARVIS Probe ISO in QEMU (Core 2 class CPU, no key pressed).
#
# Usage: probe/test-boot.sh <iso> <bios|efi> [timeout-seconds]
#
# Boots the ISO with a USB stick named REPORT attached, waits for the probe to
# finish, reads the report over HTTP exactly as a person on the network would,
# checks that it names the CPU, the PCI devices, the disks and the network chip
# and that serial numbers and MAC addresses are removed, powers the machine off,
# and checks that the stick holds a copy.
set -euo pipefail

ISO=$(readlink -f "${1:?usage: test-boot.sh <iso> <bios|efi> [timeout]}")
MODE=${2:?usage: test-boot.sh <iso> <bios|efi> [timeout]}
TIMEOUT=${3:-420}
LOG="probe-serial-$MODE.log"
SOCK="$(mktemp -u /tmp/pmon.XXXXXX).sock"
WORK=$(mktemp -d)
IMG="$WORK/report.img"
PORT=18080
truncate -s 64M "$IMG"
mkfs.vfat -n REPORT "$IMG" > /dev/null
: > "$LOG"

clean() { tr -d '\r' < "$LOG" | sed -E 's/\x1b\[[0-9;?!]*[a-zA-Z]//g'; }
monitor() { printf '%s\n' "$1" | timeout 5 socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1 || true; }
fail() {
  echo "FAIL: $*"
  CTX=$( { clean | grep -aE 'jarvis|JARVIS|probe|Failed|failed|networkd|login:|Reached target' | tail -n 25; echo '-----'; clean | tail -n 12; } 2> /dev/null \
    | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  printf '::error title=probe boot test %s::%s %%0A%s\n' "$MODE" "$*" "$CTX"
  exit 1
}

ACCEL=tcg
[ -w /dev/kvm ] && ACCEL=kvm
echo "mode=$MODE accel=$ACCEL cpu=Penryn timeout=${TIMEOUT}s"

ARGS=(-machine "pc,accel=$ACCEL" -cpu Penryn -smp 2 -m 1536
  -display none -serial "file:$LOG" -no-reboot
  -monitor "unix:$SOCK,server=on,wait=off"
  -cdrom "$ISO" -boot d
  -device usb-ehci,id=ehci -drive "file=$IMG,if=none,id=stick,format=raw" -device usb-storage,bus=ehci.0,drive=stick
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:8080" -device e1000,netdev=n0)
case "$MODE" in
  bios) ;;
  efi)
    FW=""
    for f in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF.fd /usr/share/qemu/OVMF.fd; do
      [ -f "$f" ] && FW=$f && break
    done
    [ -n "$FW" ] || { echo "OVMF firmware not found (apt install ovmf)" >&2; exit 2; }
    ARGS+=(-bios "$FW")
    ;;
  *) echo "mode must be bios or efi" >&2; exit 2 ;;
esac

qemu-system-x86_64 "${ARGS[@]}" &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT

waitfor() { # pattern seconds description
  local t=0 text
  while [ "$t" -lt "$2" ]; do
    text=$(clean || true)
    if grep -aqE "$1" <<< "$text"; then return 0; fi
    kill -0 "$QPID" 2> /dev/null || fail "the VM exited while waiting for: $3"
    sleep 3
    t=$((t + 3))
  done
  fail "timed out after $2 s waiting for: $3"
}

waitfor 'JARVIS-PROBE: DONE' "$TIMEOUT" "the probe to finish (no key may be needed at the boot menu)"
waitfor 'JARVIS-PROBE: SAVED' 120 "the report to be copied to the USB stick named REPORT"

# The screen summary (it also goes to the serial port).
SCREEN=$(clean || true)
grep -aq 'what this computer reports' <<< "$SCREEN" || fail "the on-screen summary was not shown"

# The report, fetched like a person on the network would.
REPORT="$WORK/report.txt"
t=0
until curl -fsS --max-time 10 -o "$REPORT" "http://127.0.0.1:$PORT/report.txt" 2> /dev/null; do
  t=$((t + 3))
  [ "$t" -lt 90 ] || fail "the report is not served on port 8080"
  sleep 3
done
echo "report: $(wc -l < "$REPORT") lines, $(stat -c %s "$REPORT") bytes"

need() { grep -qE "$1" "$REPORT" || fail "the report is missing: $2"; }
forbid() { if grep -qE "$1" "$REPORT"; then fail "the report must not contain: $2"; fi; }
need '^== CPU ==' 'CPU section'
need 'Penryn|Core 2' 'the CPU model (the VM is a Penryn)'
need 'sse4_1=yes' 'instruction-set readout (SSE4.1)'
need 'avx=no' 'instruction-set readout (no AVX)'
need '^== Machine ==' 'machine section'
need '^== PCI devices' 'PCI section'
need '8086:100e' 'the Ethernet chip id (QEMU e1000 is 8086:100e)'
need '^== Storage ==' 'storage section'
need '^== Network ==' 'network section'
need '^== Firmware and boot entries ==' 'firmware section'
need '^== Audio ==' 'audio section'
need '^== USB ==' 'USB section'
if [ "$MODE" = efi ]; then need 'boot mode: UEFI' 'UEFI boot mode'; else need 'boot mode: legacy BIOS' 'BIOS boot mode'; fi
need '52:54:00:xx:xx:xx' 'a MAC address with its second half removed'
forbid '52:54:00:12:34:56' 'a full MAC address'
forbid 'UUID: [0-9a-fA-F]{8}-' 'a machine UUID'
forbid 'Serial Number: *[A-Za-z0-9]' 'a serial number'
curl -fsS --max-time 10 -o "$WORK/dmesg.txt" "http://127.0.0.1:$PORT/dmesg.txt" || fail "the kernel log is not served"
[ -s "$WORK/dmesg.txt" ] || fail "the kernel log is empty"

# Power off through the firmware's button, then look at the stick.
monitor "system_powerdown"
t=0
while kill -0 "$QPID" 2> /dev/null && [ "$t" -lt 90 ]; do
  sleep 3
  t=$((t + 3))
done
kill -0 "$QPID" 2> /dev/null && { monitor "quit"; sleep 2; }
NAMES=$(mdir -b -i "$IMG" :: 2>&1 || true)
grep -q 'jarvis-probe-' <<< "$NAMES" || fail "the USB stick holds no report (found: $NAMES)"
mcopy -i "$IMG" "::/jarvis-probe-*.txt" "$WORK/" 2> /dev/null || fail "cannot read the report back from the stick"
COPY=""
for f in "$WORK"/jarvis-probe-*.txt; do
  case "$f" in
    *-dmesg.txt) ;; # the kernel log copy has no sections
    *) COPY=$f ;;
  esac
done
[ -n "$COPY" ] || fail "the stick holds a kernel log but no report"
grep -q '^== CPU ==' "$COPY" || fail "the copy on the stick has no CPU section"
echo "RESULT: PASS ($MODE: report served and saved; $(wc -l < "$REPORT") lines)"
