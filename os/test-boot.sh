#!/usr/bin/env bash
# Boot a JARVIS OS ISO (built with --selftest) in QEMU as a Core 2-class CPU
# and wait for the image's own self-test verdict on the serial console.
#
# Usage: os/test-boot.sh <iso> <bios|efi> [timeout-seconds]
#
# The CPU model is Penryn: the Core 2 generation (SSE4.1, no SSE4.2, no AVX).
# A binary or userland that needs newer instructions dies with an illegal
# instruction here, as it would on the Mac mini. This is an approximation of
# the real chip, not a substitute for testing on it.
set -euo pipefail

ISO=$(readlink -f "${1:?usage: test-boot.sh <iso> <bios|efi> [timeout]}")
MODE=${2:?usage: test-boot.sh <iso> <bios|efi> [timeout]}
TIMEOUT=${3:-900}
LOG="serial-$MODE.log"
: > "$LOG"

ACCEL=tcg
if [ -w /dev/kvm ]; then ACCEL=kvm; fi
echo "mode=$MODE accel=$ACCEL cpu=Penryn timeout=${TIMEOUT}s"

ARGS=(-machine "pc,accel=$ACCEL" -cpu Penryn -smp 2 -m 1536
      -display none -serial "file:$LOG" -no-reboot
      -cdrom "$ISO" -boot d
      -netdev user,id=n0 -device e1000,netdev=n0)

case "$MODE" in
  bios) ;;
  efi)
    FW=""
    for f in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF.fd /usr/share/qemu/OVMF.fd; do
      [ -f "$f" ] && FW=$f && break
    done
    [ -n "$FW" ] || { echo "OVMF firmware not found (apt install ovmf)" >&2; exit 2; }
    ARGS+=(-bios "$FW") ;;
  *) echo "mode must be bios or efi" >&2; exit 2 ;;
esac

qemu-system-x86_64 "${ARGS[@]}" &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT

RESULT="TIMEOUT"
START=$SECONDS
while [ $((SECONDS - START)) -lt "$TIMEOUT" ]; do
  if grep -q 'JARVIS-SELFTEST: PASS' "$LOG"; then RESULT=PASS; break; fi
  if grep -q 'JARVIS-SELFTEST: FAIL' "$LOG"; then RESULT=FAIL; break; fi
  kill -0 "$QPID" 2>/dev/null || { RESULT="VM-EXITED"; break; }
  sleep 5
done

echo "---- serial console (last 70 lines) ----"
tail -n 70 "$LOG" | tr -d '\r'
echo "----------------------------------------"
echo "result: $RESULT after $((SECONDS - START))s"

if [ "$RESULT" != "PASS" ]; then
  printf '::error title=boot test %s: %s::%s\n' "$MODE" "$RESULT" \
    "$(tail -n 25 "$LOG" | tr -d '\r' | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
  exit 1
fi
