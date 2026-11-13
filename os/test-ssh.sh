#!/usr/bin/env bash
# Boot a JARVIS OS ISO that was built with --ssh-key and prove the SSH access:
#   * the key logs in as jarvis-admin and can run root commands through sudo,
#   * a password login is refused, root login is refused, a wrong key is refused.
#
# Usage: os/test-ssh.sh <iso> <private-key-matching-the-built-in-public-key> [timeout]
# Boots in QEMU as a Core 2 (Penryn) CPU, BIOS, forwarding host port 2222 to 22.
set -euo pipefail

ISO=$(readlink -f "${1:?usage: test-ssh.sh <iso> <private-key> [timeout]}")
KEY=$(readlink -f "${2:?usage: test-ssh.sh <iso> <private-key> [timeout]}")
TIMEOUT=${3:-420}
LOG="serial-ssh.log"
: > "$LOG"

ACCEL=tcg
if [ -w /dev/kvm ]; then ACCEL=kvm; fi
echo "accel=$ACCEL cpu=Penryn timeout=${TIMEOUT}s"

qemu-system-x86_64 -machine "pc,accel=$ACCEL" -cpu Penryn -smp 2 -m 1536 \
  -display none -serial "file:$LOG" -no-reboot \
  -cdrom "$ISO" -boot d \
  -netdev "user,id=n0,hostfwd=tcp:127.0.0.1:2222-:22" -device e1000,netdev=n0 &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true' EXIT

fail() {
  echo "FAIL: $*"
  tr -d '\r' < "$LOG" | tail -n 30
  printf '::error title=ssh test::%s\n' "$*"
  exit 1
}

SSH=(ssh -p 2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR
         -o ConnectTimeout=8 -o BatchMode=yes)

echo "== waiting for SSH with the key"
START=$SECONDS
OUT=""
while [ $((SECONDS - START)) -lt "$TIMEOUT" ]; do
  kill -0 "$QPID" 2>/dev/null || fail "the VM exited before SSH came up"
  if OUT=$("${SSH[@]}" -i "$KEY" -o IdentitiesOnly=yes jarvis-admin@127.0.0.1 \
        'id -un; sudo -n id -un; sudo -n home-ai version' 2>/dev/null); then break; fi
  OUT=""
  sleep 5
done
[ -n "$OUT" ] || fail "no SSH login with the key within ${TIMEOUT}s"
echo "$OUT"
[ "$(sed -n 1p <<< "$OUT")" = "jarvis-admin" ] || fail "logged in as the wrong user"
[ "$(sed -n 2p <<< "$OUT")" = "root" ] || fail "sudo did not give root"
grep -q '^home-ai ' <<< "$OUT" || fail "the home-ai command did not answer through sudo"
echo "key login works after $((SECONDS - START))s"

echo "== things that must be refused"
if "${SSH[@]}" -o PreferredAuthentications=password -o PubkeyAuthentication=no jarvis-admin@127.0.0.1 true 2>/dev/null; then
  fail "password authentication was accepted"
fi
echo "password login refused"
if "${SSH[@]}" -i "$KEY" -o IdentitiesOnly=yes root@127.0.0.1 true 2>/dev/null; then
  fail "root login was accepted"
fi
echo "root login refused"
WRONG=$(mktemp -u); ssh-keygen -q -t ed25519 -N '' -f "$WRONG"
if "${SSH[@]}" -i "$WRONG" -o IdentitiesOnly=yes jarvis-admin@127.0.0.1 true 2>/dev/null; then
  fail "a key that was not built in was accepted"
fi
echo "unknown key refused"

echo "== sshd settings in effect"
"${SSH[@]}" -i "$KEY" -o IdentitiesOnly=yes jarvis-admin@127.0.0.1 'sudo -n sshd -T' 2>/dev/null \
  | grep -E '^(passwordauthentication|permitrootlogin|authenticationmethods|allowusers|kbdinteractiveauthentication) ' || true

echo "RESULT: PASS (ssh) in $((SECONDS - START))s"
