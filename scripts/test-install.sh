#!/usr/bin/env bash
# Installs, updates, rolls back and uninstalls Home AI for real on this machine.
# FOR THROWAWAY MACHINES ONLY (CI runners): it creates a system account, a
# systemd service and files under /opt, /etc and /var/lib, and removes them.
#
# Usage: scripts/test-install.sh <home-ai-binary> <web-dist-dir>
# Needs passwordless sudo and systemd. Test bundles are signed with a throwaway
# key through the scripts' CI-only test hook; real Sigstore signing and its
# verification are exercised by the Release workflow (scripts/release-sign.sh).
set -euo pipefail

[ "${CI:-}" = "true" ] || { echo "Refusing to run outside CI (set CI=true to override)." >&2; exit 1; }

BIN=$(readlink -f "${1:?usage: test-install.sh <binary> <web-dist>}")
WEB=$(readlink -f "${2:?usage: test-install.sh <binary> <web-dist>}")
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO"

W=$(mktemp -d)
URL=https://localhost:8443
PASSWORD='correct horse battery staple'
JAR=$W/cookies

CURRENT_STEP="start"
step() { CURRENT_STEP=$*; printf '\n=== %s\n' "$*"; }

# Failures are also emitted as GitHub annotations, which show on the run's
# summary page without opening the log.
annotate_tail() {
  local f
  f=$(ls -t "$W"/*.log 2>/dev/null | head -n 1 || true)
  [ -n "$f" ] || return 0
  printf '::error title=last output (%s)::%s\n' "$(basename "$f")" \
    "$(tail -n 25 "$f" | sed 's/%/%25/g' | awk '{printf "%s%%0A", $0}')"
}
fail() {
  printf 'FAIL: %s\n' "$*" >&2
  printf '::error title=install test failed::step "%s": %s\n' "$CURRENT_STEP" "$*"
  annotate_tail
  sudo journalctl -u home-ai -n 40 --no-pager >&2 || true
  exit 1
}
trap 'rc=$?; printf "::error title=install test error::step \"%s\", line %s: %s (exit %s)\n" "$CURRENT_STEP" "$LINENO" "$BASH_COMMAND" "$rc"; annotate_tail' ERR
req()  { curl --silent --show-error --max-time 10 --cacert "$W/cert.pem" "$@"; }
code() { req --output /dev/null --write-out '%{http_code}' "$@"; }
healthy() {
  for _ in $(seq 1 40); do
    if req "$URL/api/health" 2>/dev/null; then return 0; fi
    sleep 0.5
  done
  return 1
}
expect_refused() { # <description> <command...>
  local what=$1; shift
  if "$@" > "$W/refused.log" 2>&1; then cat "$W/refused.log"; fail "$what was accepted"; fi
  [ ! -e /opt/home-ai ] || fail "$what left files in /opt/home-ai"
  # A crash is not a refusal: the script must have stopped on purpose.
  grep -q '^ERROR: ' "$W/refused.log" || fail "$what: installer stopped without an ERROR message"
  echo "refused as expected: $(grep -m1 '^ERROR: ' "$W/refused.log")"
}

step "build test bundles signed with a throwaway key"
openssl genpkey -algorithm ed25519 -out "$W/key.pem"
openssl pkey -in "$W/key.pem" -pubout -out "$W/pub.pem"
openssl genpkey -algorithm ed25519 -out "$W/other.pem"
openssl pkey -in "$W/other.pem" -pubout -out "$W/other.pub.pem"
GOOD=$(TEST_SIGNING_KEY_FILE=$W/key.pem bash scripts/package.sh "$BIN" "$WEB" "$W/good" | tail -n 1)
VERSION=$("$BIN" version | awk '{print $2}')

# A "release" that reports a version but cannot serve: for the rollback test.
cat > "$W/broken-home-ai" <<'EOF'
#!/bin/sh
[ "$1" = "version" ] && { echo "home-ai 9.9.9"; exit 0; }
exit 1
EOF
chmod +x "$W/broken-home-ai"
BROKEN=$(TEST_SIGNING_KEY_FILE=$W/key.pem bash scripts/package.sh "$W/broken-home-ai" "$WEB" "$W/broken" | tail -n 1)

# sudo drops the environment, so the CI test hook has to be passed explicitly.
# Without these two variables the scripts use the production Sigstore path.
# The installer that ships INSIDE the bundle is the one under test: this is what
# get.sh runs on a real server, so its relative paths must work unpacked.
LISTING=$(tar tzf "$GOOD")
grep -q '/installer/install.sh$' <<< "$LISTING" || fail "bundle does not contain installer/install.sh"
mkdir -p "$W/unpacked"
tar -xzf "$GOOD" -C "$W/unpacked"
BUNDLED=$(echo "$W"/unpacked/*/installer)
[ -x "$BUNDLED/install.sh" ] && [ -x "$BUNDLED/update.sh" ] && [ -f "$BUNDLED/packaging/lib.sh" ] \
  && [ -f "$BUNDLED/packaging/home-ai.service" ] && [ -f "$BUNDLED/packaging/home-ai.env.template" ] \
  || fail "bundled installer is incomplete"
INSTALL=(sudo CI=true "HOME_AI_TEST_PUBKEY=$W/pub.pem" "$BUNDLED/install.sh")
UPDATE=(sudo CI=true "HOME_AI_TEST_PUBKEY=$W/pub.pem" "$BUNDLED/update.sh")

step "production path: a bundle with no Sigstore evidence is refused"
expect_refused "bundle without .sigstore.json" sudo ./install.sh --bundle "$GOOD"

step "production path: forged evidence is refused by the pinned cosign"
cp -r "$W/good" "$W/forged"
printf '{}\n' > "$W/forged/$(basename "$GOOD").sigstore.json"
expect_refused "bundle with forged Sigstore evidence" sudo ./install.sh --bundle "$W/forged/$(basename "$GOOD")"
COSIGN_BIN=$(ls /usr/local/lib/home-ai/cosign-v* 2>/dev/null | head -n 1)
[ -n "$COSIGN_BIN" ] || fail "the pinned cosign was not fetched"
PINNED=$(sed -n 's/^COSIGN_SHA256=//p' packaging/lib.sh)
[ "$(sha256sum "$COSIGN_BIN" | awk '{print $1}')" = "$PINNED" ] || fail "installed cosign does not match the pinned checksum"

step "test path: bundles that fail the signature check are refused"
expect_refused "bundle signed by a different key" \
  sudo CI=true "HOME_AI_TEST_PUBKEY=$W/other.pub.pem" ./install.sh --bundle "$GOOD"

cp -r "$W/good" "$W/nosig"; rm "$W/nosig/$(basename "$GOOD").testsig"
expect_refused "bundle with no signature" "${INSTALL[@]}" --bundle "$W/nosig/$(basename "$GOOD")"

cp -r "$W/good" "$W/altered"; printf 'x' >> "$W/altered/$(basename "$GOOD")"
expect_refused "altered bundle" "${INSTALL[@]}" --bundle "$W/altered/$(basename "$GOOD")"

step "install"
"${INSTALL[@]}" --bundle "$GOOD" | tee "$W/install.log"
grep -q 'Installation completed successfully' "$W/install.log" || fail "no success message"
grep -q 'Status: RUNNING' "$W/install.log" || fail "no status line"
TOKEN=$(grep -Eo '^\s+[0-9a-f]{64}$' "$W/install.log" | tr -d ' ')
[ -n "$TOKEN" ] || fail "installer printed no setup token"
PRINTED_FP=$(grep -Eo '([0-9A-F]{2}:){31}[0-9A-F]{2}' "$W/install.log" | head -n 1)
[ -n "$PRINTED_FP" ] || fail "installer printed no fingerprint"

step "service, account and permissions"
systemctl is-active --quiet home-ai || fail "service not active"
systemctl is-enabled --quiet home-ai || fail "service not enabled at boot"
[ "$(ps -o user= -p "$(systemctl show -p MainPID --value home-ai)" | tr -d ' ')" = "home-ai" ] \
  || fail "service is not running as the home-ai account"
[ "$(getent passwd home-ai | cut -d: -f7)" = "/usr/sbin/nologin" ] || fail "service account can log in"
[ "$(sudo stat -c '%a %U' /var/lib/home-ai/tls/key.pem)" = "600 home-ai" ] || fail "private key permissions"
[ "$(sudo stat -c '%a %U:%G' /etc/home-ai/home-ai.env)" = "640 root:home-ai" ] || fail "settings file permissions"
[ "$(sudo stat -c '%U' /opt/home-ai/bin/home-ai)" = "root" ] || fail "binary not owned by root"
[ "$(cat /opt/home-ai/VERSION)" = "$VERSION" ] || fail "wrong installed version"

step "HTTPS verifies against the installed certificate, and matches the printed fingerprint"
sudo cat /var/lib/home-ai/tls/cert.pem > "$W/cert.pem"
healthy | grep -q '"setup_required":true' || fail "health check / setup state"
SERVED_FP=$(echo | openssl s_client -connect 127.0.0.1:8443 -servername localhost 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)
[ "$SERVED_FP" = "$PRINTED_FP" ] || fail "served fingerprint differs from the one the installer printed"
ss -ltn | grep -q '0.0.0.0:8443' || fail "not listening on the network address"

step "complete setup with the printed token, sign in, send a command"
BODY=$(printf '{"setup_token":"%s","username":"admin","password":"%s"}' "$TOKEN" "$PASSWORD")
[ "$(code -X POST -H 'content-type: application/json' -d "$BODY" "$URL/api/setup")" = "201" ] || fail "setup"
LOGIN=$(printf '{"username":"admin","password":"%s"}' "$PASSWORD")
[ "$(code -c "$JAR" -X POST -H 'content-type: application/json' -d "$LOGIN" "$URL/api/login")" = "200" ] || fail "login"
req -b "$JAR" -X POST -H 'content-type: application/json' -d '{"action":"set_brightness","percent":37}' \
  "$URL/api/devices/sim-light-living/actions" | grep -q '"outcome":"confirmed"' || fail "device command"
req "$URL/" | grep -q '<div id="app">' || fail "dashboard not served"

step "running install.sh again is refused and changes nothing"
if "${INSTALL[@]}" --bundle "$GOOD" > "$W/again.log" 2>&1; then fail "second install was accepted"; fi
grep -q 'update.sh' "$W/again.log" || fail "second install did not point to update.sh"
systemctl is-active --quiet home-ai || fail "service stopped by refused install"

step "a crash restarts the service and does not reopen setup"
sudo systemctl kill --signal=KILL home-ai
sleep 4
healthy | grep -q '"setup_required":false' || fail "not healthy after crash, or setup reopened"
if sudo home-ai setup-token > /dev/null 2>&1; then fail "a setup token was issued after setup"; fi
req -b "$JAR" "$URL/api/devices" | grep -q '"brightness":37' || fail "state lost across crash"

step "update keeps data; --rollback returns to the previous files and database"
"${UPDATE[@]}" --bundle "$GOOD" | tee "$W/update.log"
grep -q 'Update completed' "$W/update.log" || fail "update did not complete"
healthy > /dev/null || fail "unhealthy after update"
req -b "$JAR" "$URL/api/devices" | grep -q '"brightness":37' || fail "state lost across update"
sudo test -f "$(sudo readlink -f /var/lib/home-ai/backups/last-pre-update)/home-ai.db" || fail "no pre-update database copy"
req -b "$JAR" -X POST -H 'content-type: application/json' -d '{"action":"set_brightness","percent":88}' \
  "$URL/api/devices/sim-light-living/actions" | grep -q '"outcome":"confirmed"' || fail "command after update"
sudo ./update.sh --rollback
healthy > /dev/null || fail "unhealthy after rollback"
req -b "$JAR" "$URL/api/devices" | grep -q '"brightness":37' || fail "rollback did not restore the pre-update database"

step "an update that cannot start is rolled back automatically"
if "${UPDATE[@]}" --bundle "$BROKEN" > "$W/broken.log" 2>&1; then cat "$W/broken.log"; fail "broken update reported success"; fi
grep -q 'rolled back' "$W/broken.log" || { cat "$W/broken.log"; fail "no rollback message"; }
healthy > /dev/null || fail "unhealthy after automatic rollback"
[ "$(cat /opt/home-ai/VERSION)" = "$VERSION" ] || fail "wrong version after automatic rollback"
req -b "$JAR" "$URL/api/devices" | grep -q '"brightness":37' || fail "state lost in automatic rollback"

step "uninstall keeps data; reinstall reuses it and does not reopen setup"
sudo ./uninstall.sh
[ ! -e /opt/home-ai ] && [ ! -e /etc/systemd/system/home-ai.service ] || fail "uninstall left program files"
sudo test -f /var/lib/home-ai/home-ai.db || fail "uninstall deleted the database"
"${INSTALL[@]}" --bundle "$GOOD" | tee "$W/reinstall.log"
grep -q 'An administrator already exists' "$W/reinstall.log" || fail "reinstall did not recognise the existing administrator"
if grep -Eq '^\s+[0-9a-f]{64}$' "$W/reinstall.log"; then fail "reinstall printed a setup token"; fi
[ "$(grep -Eo '([0-9A-F]{2}:){31}[0-9A-F]{2}' "$W/reinstall.log" | head -n 1)" = "$PRINTED_FP" ] \
  || fail "certificate changed on reinstall"
healthy | grep -q '"setup_required":false' || fail "setup reopened by reinstall"
req -b "$JAR" "$URL/api/devices" | grep -q '"brightness":37' || fail "state lost across reinstall"

step "uninstall --purge removes everything"
sudo ./uninstall.sh --purge --yes
for path in /opt/home-ai /etc/home-ai /var/lib/home-ai /usr/local/lib/home-ai /usr/local/bin/home-ai /etc/systemd/system/home-ai.service; do
  sudo test ! -e "$path" || fail "$path still exists after purge"
done
if id home-ai > /dev/null 2>&1; then fail "service account still exists after purge"; fi

printf '\nINSTALL TEST PASSED\n'
