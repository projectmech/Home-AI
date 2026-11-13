#!/usr/bin/env bash
# Black-box test of the real JARVIS OS ISO in QEMU. No test hooks in the image:
# it checks what a person at the machine, and a browser on the network, would see.
#
# Usage: os/test-boot.sh <iso> <bios|efi> [timeout-seconds]
#
# - CPU model Penryn: Core 2 generation (SSE4.1, no SSE4.2, no AVX).
# - No key is ever pressed: the boot menu must start the system by itself.
# - The console banner (serial port) must show the address, setup token and
#   certificate fingerprint; then, from outside the VM:
#     * the fingerprint the server really presents equals the printed one,
#     * /api/health answers and setup is open,
#     * the printed token is accepted by the setup endpoint, a wrong one is not,
#     * the dashboard is served.
set -euo pipefail

ISO=$(readlink -f "${1:?usage: test-boot.sh <iso> <bios|efi> [timeout]}")
MODE=${2:?usage: test-boot.sh <iso> <bios|efi> [timeout]}
TIMEOUT=${3:-420}
LOG="serial-$MODE.log"
SOCK="$(mktemp -u /tmp/qmon.XXXXXX).sock"
PORT=18443
: > "$LOG"

monitor() { printf '%s\n' "$1" | timeout 5 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1 || true; }
fail() {
  echo "FAIL: $*"
  monitor "screendump screen-$MODE.ppm"; sleep 1
  # Put the useful serial lines into the failure message itself.
  CTX=$( { clean | grep -aE 'jarvis|JARVIS|home-ai|Failed|failed|networkd|DHCP|dhcp|Dashboard|Setup token|ttyS0|Reached target|login:' | tail -n 30; echo '-----'; clean | tail -n 12; } 2>/dev/null \
    | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  printf '::error title=boot test %s::%s %%0A%s\n' "$MODE" "$*" "$CTX"
  exit 1
}

ACCEL=tcg
if [ -w /dev/kvm ]; then ACCEL=kvm; fi
echo "mode=$MODE accel=$ACCEL cpu=Penryn timeout=${TIMEOUT}s"

ARGS=(-machine "pc,accel=$ACCEL" -cpu Penryn -smp 2 -m 1536
      -display none -serial "file:$LOG" -no-reboot
      -monitor "unix:$SOCK,server=on,wait=off"
      -cdrom "$ISO" -boot d
      -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:8443" -device e1000,netdev=n0)

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

clean() { tr -d '\r' < "$LOG" | sed -E 's/\x1b\[[0-9;?!]*[a-zA-Z]//g; s/\x1b\][0-9;]*[^\x07]*\x07?//g'; }

# ---- 1. wait for the console banner ----
START=$SECONDS
TOKEN=""; FP=""; ADDR=""
NEEDED_ENTER=0
while [ $((SECONDS - START)) -lt "$TIMEOUT" ]; do
  kill -0 "$QPID" 2>/dev/null || fail "the VM exited before the banner appeared"
  # If nothing has appeared after 100 s, press Enter once. That separates "the
  # boot menu waits for a key" from "the banner is broken"; the run still fails.
  if [ $((SECONDS - START)) -ge 100 ] && [ "$NEEDED_ENTER" = 0 ] && [ -z "$TOKEN" ]; then
    echo "no banner after 100 s: pressing Enter once to see whether the boot menu was waiting"
    monitor "sendkey ret"; NEEDED_ENTER=1
  fi
  TEXT=$(clean || true)
  TOKEN=$(grep -Eo 'Setup token: +[0-9a-f]{64}' <<< "$TEXT" | tail -n 1 | grep -Eo '[0-9a-f]{64}' || true)
  FP=$(grep -Eo 'Certificate SHA-256: +([0-9A-F]{2}:){31}[0-9A-F]{2}' <<< "$TEXT" | tail -n 1 | grep -Eo '([0-9A-F]{2}:){31}[0-9A-F]{2}' || true)
  ADDR=$(grep -Eo 'Dashboard: +https://[0-9.]+:8443' <<< "$TEXT" | tail -n 1 | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || true)
  if [ -n "$TOKEN" ] && [ -n "$FP" ] && [ -n "$ADDR" ]; then break; fi
  sleep 5
done
echo "---- console (last 45 lines, cleaned) ----"
clean | tail -n 45
echo "------------------------------------------"
[ -n "$TOKEN" ] || fail "no setup token on the console after ${TIMEOUT}s (did the menu start by itself?)"
[ -n "$FP" ] || fail "no certificate fingerprint on the console"
[ -n "$ADDR" ] || fail "no IPv4 address on the console (DHCP did not work)"
echo "banner: address=$ADDR fingerprint=$FP token=<64 hex>"
echo "booted and showed the banner after $((SECONDS - START))s"

# ---- 2. checks from outside the VM ----
URL="https://127.0.0.1:$PORT"
SERVED=$(echo | timeout 20 openssl s_client -connect "127.0.0.1:$PORT" -servername jarvis 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true)
[ "$SERVED" = "$FP" ] || fail "the certificate the server presents ($SERVED) is not the one on the console ($FP)"
echo "served certificate matches the console fingerprint"

HEALTH=$(curl -sk --max-time 10 "$URL/api/health" || true)
echo "health: $HEALTH"
grep -q '"status":"ok"' <<< "$HEALTH" || fail "health check failed"
grep -q '"setup_required":true' <<< "$HEALTH" || fail "setup should be open on a fresh image"

CODE=$(curl -sk --max-time 10 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
  -d "{\"setup_token\":\"$(printf '%064d' 0)\"}" "$URL/api/setup/verify" || true)
[ "$CODE" = "403" ] || fail "a wrong setup token was not refused (HTTP $CODE)"
RESP=$(curl -sk --max-time 10 -X POST -H 'content-type: application/json' \
  -d "{\"setup_token\":\"$TOKEN\"}" "$URL/api/setup/verify" || true)
grep -q '"mem_total_bytes"' <<< "$RESP" || fail "the token shown on the console was not accepted: $RESP"
echo "console token accepted by the setup endpoint; wrong token refused"

curl -sk --max-time 10 "$URL/" | grep -q '<div id="app">' || fail "dashboard page not served"
curl -skI --max-time 10 "$URL/" | grep -qi '^content-security-policy:' || fail "no security headers"
echo "dashboard served with security headers"

[ "$NEEDED_ENTER" = 0 ] || fail "everything works, but only after pressing Enter: the boot menu does not start by itself"
echo "RESULT: PASS ($MODE) in $((SECONDS - START))s"
