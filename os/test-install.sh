#!/usr/bin/env bash
# End-to-end test of the JARVIS OS installer in QEMU (a Core 2 CPU model).
#
# Usage: os/test-install.sh <iso> <bios|efi> <pass|recovery> [splash]
#
# With "splash" the installed system starts with the JARVIS logo boot screen
# (EFI only): the test checks the mark is drawn (solid bright areas, not console
# text), then types the passphrase through the virtual keyboard, because with
# a splash the unlock prompt is on the screen, not on the serial console.
#
#  A. Boot the ISO in installer mode (jarvis.install=auto, test only) onto an
#     empty virtual disk and wait for "JARVIS-INSTALL: DONE". The installer
#     must have run in the requested boot mode.
#  B. Boot the INSTALLED disk with the real boot loader. Unlock it with the
#     passphrase at the prompt. Check the console box, the certificate
#     fingerprint, that setup is open and the token works; create the
#     administrator; power off cleanly.
#  C. Boot again and unlock with the passphrase (mode "pass") or with the
#     RECOVERY KEY the installer printed (mode "recovery"). Check that the
#     administrator and the certificate survived the reboot (encrypted data
#     persists) and that setup stays closed.
set -euo pipefail

ISO=$(readlink -f "${1:?usage: test-install.sh <iso> <bios|efi> <pass|recovery>}")
MODE=${2:?}
UNLOCK=${3:?}
SPLASH=${4:-}
TAG="$MODE-$UNLOCK${SPLASH:+-splash}"
PORT=18443
PASSPHRASE='jarvis-test-passphrase'
ADMINPW='correct horse battery staple'
WORK=$(mktemp -d)
DISK="$WORK/disk.qcow2"
qemu-img create -q -f qcow2 "$DISK" 20G

ACCEL=tcg; [ -w /dev/kvm ] && ACCEL=kvm
COMMON=(-machine "pc,accel=$ACCEL" -cpu Penryn -smp 2 -m 3072 -display none -no-reboot)
EFI=()
if [ "$MODE" = efi ]; then
  FW=""
  for f in /usr/share/ovmf/OVMF.fd /usr/share/OVMF/OVMF.fd /usr/share/qemu/OVMF.fd; do [ -f "$f" ] && FW=$f && break; done
  [ -n "$FW" ] || { echo "OVMF not found" >&2; exit 2; }
  EFI=(-bios "$FW")
fi
echo "mode=$MODE unlock-with=$UNLOCK splash=${SPLASH:-no} accel=$ACCEL"

QPID=""
trap '[ -z "$QPID" ] || kill "$QPID" 2>/dev/null || true' EXIT

clean() { tr -d '\r' < "$1" | sed -E 's/\x1b\[[0-9;?!]*[a-zA-Z]//g; s/\x1b\][0-9;]*[^\x07]*\x07?//g'; }
fail() {
  local log=${CURLOG:-}
  echo "FAIL: $*"
  CTX=""
  if [ -n "$log" ] && [ -f "$log" ]; then
    CTX=$( { { has_file=install-$TAG-A.log; [ -f "$has_file" ] && clean "$has_file" | grep -aE 'initramfs:' | head -n 16; } 2>/dev/null; clean "$log" | grep -aE 'jarvis|JARVIS|install|Failed|failed|error|Error|unlock|grub|cryptsetup|plymouth|Plymouth|Kernel command line|display:|dmesg:|plog:' | tail -n 40; echo '-----'; clean "$log" | tail -n 12; } 2>/dev/null \
      | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')
  fi
  printf '::error title=install test %s: %s::%s %%0A%s\n' "$MODE" "$UNLOCK" "$*" "$CTX"
  exit 1
}
# Is the pattern in the cleaned log? No pipe on purpose: with pipefail, grep -q
# quitting early makes the writer die of SIGPIPE and the test reports a false miss
# once the log is big.
has() { # <pattern> <log>
  local tmp rc; tmp=$(mktemp); clean "$2" > "$tmp" 2>/dev/null || true
  grep -aqE "$1" "$tmp"; rc=$?; rm -f "$tmp"; return $rc
}
waitfor() { # <log> <pattern> <seconds> <description>
  local t=0
  while [ "$t" -lt "$3" ]; do
    has "$2" "$1" && return 0
    if [ -n "$QPID" ] && ! kill -0 "$QPID" 2>/dev/null; then has "$2" "$1" && return 0; fail "the VM exited while waiting for: $4"; fi
    sleep 3; t=$((t + 3))
  done
  fail "timed out after $3 s waiting for: $4"
}

# ---------------------------------------------------------------- A. install
echo "== A. installing onto an empty disk ($MODE)"
xorriso -osirrox on -indev "$ISO" -extract /live/vmlinuz "$WORK/vmlinuz" -extract /live/initrd.img "$WORK/initrd.img" >/dev/null 2>&1
CURLOG="install-$TAG-A.log"; : > "$CURLOG"
APPEND="boot=live components hostname=jarvis nomodeset plymouth.enable=0 console=ttyS0,115200n8 jarvis.install=auto jarvis.install.disk=/dev/vda jarvis.install.erase=ERASE-/dev/vda jarvis.install.pass=$PASSPHRASE"
[ -z "$SPLASH" ] || APPEND="$APPEND jarvis.install.splash=1"
qemu-system-x86_64 "${COMMON[@]}" "${EFI[@]}" -serial "file:$CURLOG" \
  -kernel "$WORK/vmlinuz" -initrd "$WORK/initrd.img" -append "$APPEND" \
  -cdrom "$ISO" -drive "file=$DISK,if=virtio,format=qcow2" \
  -netdev user,id=n0 -device e1000,netdev=n0 &
QPID=$!
waitfor "$CURLOG" 'JARVIS-INSTALL: (DONE|FAIL)' 1200 "the installer to finish"
has 'JARVIS-INSTALL: DONE' "$CURLOG" || fail "the installer reported a failure"
has "Boot mode of this computer: $MODE" "$CURLOG" || fail "the installer did not run in $MODE mode"
RECOVERY=$(clean "$CURLOG" | sed -n 's/.*JARVIS-INSTALL: RECOVERY-KEY \([A-Z2-9-]*\).*/\1/p' | tail -n 1)
[ "${#RECOVERY}" -eq 39 ] || fail "no recovery key was printed"
for _ in $(seq 1 40); do kill -0 "$QPID" 2>/dev/null || break; sleep 3; done
kill -0 "$QPID" 2>/dev/null && fail "the VM did not power off after the install"
QPID=""
echo "installed; recovery key has the right shape"

# ------------------------------------------- the boot splash (EFI, "splash" only)
monitor() { printf '%s\n' "$1" | timeout 10 socat - "UNIX-CONNECT:$MSOCK" >/dev/null 2>&1 || true; }

# Pixels in long bright horizontal runs (20 or more in a row): the mark's solid
# bars. Console text is made of strokes only 1-2 pixels wide and never counts.
blue_pixels() { # <ppm>
  local f=$1 hdr skip w
  [ -s "$f" ] || { echo 0; return; }
  hdr=$(head -n 3 "$f")
  skip=$(printf '%s
' "$hdr" | wc -c)
  w=$(sed -n 2p <<< "$hdr" | cut -d' ' -f1)
  tail -c +$((skip + 1)) "$f" | od -An -v -tu1 -w3 | awk -v w="$w" '
    { x = (NR - 1) % w
      if ($1 + $2 + $3 > 450) { run++ } else { if (run >= 20) n += run; run = 0 }
      if (x == w - 1) { if (run >= 20) n += run; run = 0 } }
    END { if (run >= 20) n += run; print n + 0 }'
}

# Type text through the virtual keyboard (the prompt is on the screen, not on
# the serial console). Only lowercase letters and '-' are needed here.
type_keys() { # <text>
  local text=$1 i ch key
  for ((i = 0; i < ${#text}; i++)); do
    ch=${text:i:1}
    case "$ch" in
      [a-z]) key=$ch ;;
      -) key=minus ;;
      *) fail "type_keys cannot type '$ch'" ;;
    esac
    monitor "sendkey $key"
    sleep 0.15
  done
  monitor "sendkey ret"
}

unlock_with_splash() { # <tag> <secret>
  local tag=$1 secret=$2 shot="install-$TAG-$tag.ppm" n=0 attempt
  waitfor "$CURLOG" 'Kernel command line' 300 "the kernel to start"
  for _ in $(seq 1 24); do
    monitor "screendump $shot"
    sleep 3
    n=$(blue_pixels "$shot")
    [ "$n" -gt 3000 ] && break
    sleep 2
  done
  echo "boot splash: $n solid bright pixels on screen"
  if [ "$n" -le 3000 ]; then
    # Diagnosis: if the unlock prompt came up on the serial console the splash did
    # not take over. Unlock that way so the system finishes booting and reports
    # its display state (the "display:" and "dmesg:" lines), then fail.
    if has 'Please unlock disk' "$CURLOG"; then
      { sleep 1; printf '%s\n' "$secret"; sleep 3; } | timeout 20 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1 || true
      for _ in $(seq 1 60); do
        has 'dmesg: |Dashboard: +https://' "$CURLOG" && break
        sleep 3
      done
      sleep 5
      fail "the boot splash did not draw the mark (solid bright pixels: $n); the unlock prompt was on the serial console instead"
    fi
    fail "the boot splash did not draw the logo (solid bright pixels: $n)"
  fi
  # The prompt may not be up yet when the splash first appears: type, and if the
  # system has not come up shortly after, type again.
  for attempt in 1 2 3; do
    sleep 6
    type_keys "$secret"
    for _ in $(seq 1 30); do
      has 'Dashboard: +https://[0-9.]+:8443' "$CURLOG" && return 0
      sleep 3
    done
  done
}

# -------------------------------------------------- boot the installed disk
boot_installed() { # <tag> <secret to type at the unlock prompt>
  local tag=$1 secret=$2
  CURLOG="install-$TAG-$tag.log"; : > "$CURLOG"
  SOCK="$WORK/ser-$tag.sock"; MSOCK="$WORK/mon-$tag.sock"
  qemu-system-x86_64 "${COMMON[@]}" "${EFI[@]}" \
    -chardev "socket,id=ser0,path=$SOCK,server=on,wait=off,logfile=$CURLOG" -serial chardev:ser0 \
    -monitor "unix:$MSOCK,server=on,wait=off" \
    -drive "file=$DISK,if=virtio,format=qcow2" \
    -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:$PORT-:8443" -device e1000,netdev=n0 &
  QPID=$!
  if [ -n "$SPLASH" ]; then
    unlock_with_splash "$tag" "$secret"
  else
    waitfor "$CURLOG" 'Please unlock disk' 300 "the disk unlock prompt (the boot loader and initramfs must work)"
    { sleep 2; printf '%s\n' "$secret"; sleep 4; } | timeout 20 socat - "UNIX-CONNECT:$SOCK" >/dev/null 2>&1 || true
  fi
  waitfor "$CURLOG" 'Dashboard: +https://[0-9.]+:8443' 300 "the console box after unlocking"
  sleep 2
  TEXT=$(clean "$CURLOG")
  TOKEN=$(grep -Eo 'Setup token: +[0-9a-f]{64}' <<< "$TEXT" | tail -n 1 | grep -Eo '[0-9a-f]{64}' || true)
  FP=$(grep -Eo 'Certificate SHA-256: +([0-9A-F]{2}:){31}[0-9A-F]{2}' <<< "$TEXT" | tail -n 1 | grep -Eo '([0-9A-F]{2}:){31}[0-9A-F]{2}' || true)
  [ -n "$FP" ] || fail "no certificate fingerprint on the console"
  grep -q 'live test image' <<< "$TEXT" && fail "the installed system still says it is a live test image"
  SERVED=$(echo | timeout 20 openssl s_client -connect "127.0.0.1:$PORT" -servername jarvis 2>/dev/null | openssl x509 -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2 || true)
  [ "$SERVED" = "$FP" ] || fail "the served certificate ($SERVED) is not the one on the console ($FP)"
}
poweroff_vm() {
  printf 'system_powerdown\n' | timeout 5 socat - "UNIX-CONNECT:$MSOCK" >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do kill -0 "$QPID" 2>/dev/null || { QPID=""; return 0; }; sleep 3; done
  fail "the installed system did not power off cleanly"
}

# --------------------------------------------- B. first boot: unlock, set up
echo "== B. first boot: unlock with the passphrase, create the administrator"
boot_installed B "$PASSPHRASE"
FP_B=$FP
[ -n "$TOKEN" ] || fail "no setup token on the console of a fresh install"
HEALTH=$(curl -sk --max-time 10 "https://127.0.0.1:$PORT/api/health" || true)
grep -q '"setup_required":true' <<< "$HEALTH" || fail "setup should be open on a fresh install: $HEALTH"
CODE=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
  -d "{\"setup_token\":\"$TOKEN\",\"username\":\"admin\",\"password\":\"$ADMINPW\"}" "https://127.0.0.1:$PORT/api/setup" || true)
[ "$CODE" = 201 ] || fail "creating the administrator failed (HTTP $CODE)"
echo "administrator created; powering off"
poweroff_vm

# -------------------------------- C. second boot: unlock again, data persists
if [ "$UNLOCK" = recovery ]; then SECRET=$RECOVERY; else SECRET=$PASSPHRASE; fi
echo "== C. second boot: unlock with the $UNLOCK, check that the data survived"
boot_installed C "$SECRET"
[ "$FP" = "$FP_B" ] || fail "the certificate changed across the reboot ($FP_B -> $FP): data did not persist"
HEALTH=$(curl -sk --max-time 10 "https://127.0.0.1:$PORT/api/health" || true)
grep -q '"setup_required":false' <<< "$HEALTH" || fail "setup is open again after the reboot: $HEALTH"
LOGIN=$(curl -sk --max-time 20 -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' \
  -d "{\"username\":\"admin\",\"password\":\"$ADMINPW\"}" "https://127.0.0.1:$PORT/api/login" || true)
[ "$LOGIN" = 200 ] || fail "the administrator created before the reboot cannot sign in (HTTP $LOGIN)"
poweroff_vm

echo "RESULT: PASS (install + unlock with $UNLOCK + persistence, $MODE)"
