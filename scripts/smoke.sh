#!/usr/bin/env bash
# End-to-end smoke test of a built binary over real HTTPS.
# Usage: scripts/smoke.sh <path-to-home-ai-binary> <path-to-web-dist>
# Uses a temporary data directory and the simulator only; touches nothing else.
set -euo pipefail

BIN=$(readlink -f "${1:?usage: smoke.sh <binary> <web-dist>}")
WEB=$(readlink -f "${2:?usage: smoke.sh <binary> <web-dist>}")
PORT=18443
URL="https://localhost:${PORT}"
PASSWORD='correct horse battery staple'

WORK=$(mktemp -d)
PID=""
cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  rm -rf "$WORK"
}
trap cleanup EXIT

export APP_DATA_DIR="$WORK/data" APP_WEB_DIR="$WEB" APP_LISTEN="127.0.0.1:${PORT}" APP_TLS=self-signed
CERT="$APP_DATA_DIR/tls/cert.pem"
JAR="$WORK/cookies"

step() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Every request verifies the server against its own certificate: no -k.
req() { curl --silent --show-error --max-time 10 --cacert "$CERT" "$@"; }
code() { req --output /dev/null --write-out '%{http_code}' "$@"; }

start_server() {
  "$BIN" &
  PID=$!
  for _ in $(seq 1 50); do
    if [ -f "$CERT" ] && req "$URL/api/health" >/dev/null 2>&1; then return 0; fi
    kill -0 "$PID" 2>/dev/null || fail "server exited during startup"
    sleep 0.2
  done
  fail "server did not become healthy"
}

step "plain HTTP on a non-loopback address is refused"
if APP_TLS=off APP_LISTEN=0.0.0.0:18080 timeout 5 "$BIN" >/dev/null 2>&1; then
  fail "server accepted plaintext on 0.0.0.0"
fi

step "certificate is created and its fingerprint is printed"
FINGERPRINT=$("$BIN" tls-fingerprint)
echo "$FINGERPRINT" | grep -Eq '^([0-9A-F]{2}:){31}[0-9A-F]{2}$' || fail "bad fingerprint: $FINGERPRINT"
[ "$(stat -c '%a' "$APP_DATA_DIR/tls/key.pem")" = "600" ] || fail "private key is not mode 600"

step "server starts and serves that certificate"
start_server
SERVED=$(echo | openssl s_client -connect "127.0.0.1:${PORT}" -servername localhost 2>/dev/null \
  | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)
[ "$SERVED" = "$FINGERPRINT" ] || fail "served $SERVED, expected $FINGERPRINT"
req "$URL/api/health" | grep -q '"setup_required":true' || fail "setup should be required"

step "frontend is served, with security headers"
req "$URL/" | grep -q '<div id="app">' || fail "index.html not served"
req --head "$URL/" | grep -qi '^content-security-policy:' || fail "no CSP header"

step "anonymous API access is refused"
[ "$(code "$URL/api/devices")" = "401" ] || fail "devices open to anonymous"

step "setup needs the one-time token"
BODY_BAD=$(printf '{"setup_token":"%064d","username":"admin","password":"%s"}' 0 "$PASSWORD")
[ "$(code -X POST -H 'content-type: application/json' -d "$BODY_BAD" "$URL/api/setup")" = "403" ] \
  || fail "setup accepted without an issued token"
TOKEN=$("$BIN" setup-token | grep -Eo '[0-9a-f]{64}')
[ "$(code -X POST -H 'content-type: application/json' -d "$BODY_BAD" "$URL/api/setup")" = "403" ] \
  || fail "setup accepted a wrong token"
BODY=$(printf '{"setup_token":"%s","username":"admin","password":"%s"}' "$TOKEN" "$PASSWORD")
[ "$(code -X POST -H 'content-type: application/json' -d "$BODY" "$URL/api/setup")" = "201" ] \
  || fail "setup with the real token failed"
[ "$(code -X POST -H 'content-type: application/json' -d "$BODY" "$URL/api/setup")" = "409" ] \
  || fail "setup could be repeated"
if "$BIN" setup-token >/dev/null 2>&1; then fail "a token was issued after setup"; fi

step "login, read devices, send a command"
LOGIN=$(printf '{"username":"admin","password":"%s"}' "$PASSWORD")
[ "$(code -c "$JAR" -X POST -H 'content-type: application/json' -d "$LOGIN" "$URL/api/login")" = "200" ] \
  || fail "login failed"
req -b "$JAR" "$URL/api/devices" | grep -q '"sim-light-living"' || fail "devices not listed"
req -b "$JAR" -X POST -H 'content-type: application/json' \
  -d '{"action":"set_brightness","percent":42}' "$URL/api/devices/sim-light-living/actions" \
  | grep -q '"outcome":"confirmed"' || fail "command not confirmed"
req -b "$JAR" "$URL/api/server/metrics" | grep -q '"mem_total_bytes"' || fail "no metrics"

step "cross-origin POST is refused"
[ "$(code -b "$JAR" -X POST -H 'origin: https://evil.example' -H 'content-type: application/json' \
  -d '{"action":"set_power","on":true}' "$URL/api/devices/sim-light-living/actions")" = "403" ] \
  || fail "cross-origin POST accepted"

step "SIGTERM stops cleanly; restart keeps state, session and certificate"
kill -TERM "$PID"
wait "$PID" || fail "server exited non-zero on SIGTERM"
PID=""
start_server
[ "$("$BIN" tls-fingerprint)" = "$FINGERPRINT" ] || fail "certificate changed across restart"
req "$URL/api/health" | grep -q '"setup_required":false' || fail "setup reopened after restart"
req -b "$JAR" "$URL/api/devices" | grep -q '"brightness":42' || fail "device state lost on restart"

printf '\nSMOKE TEST PASSED\n'
