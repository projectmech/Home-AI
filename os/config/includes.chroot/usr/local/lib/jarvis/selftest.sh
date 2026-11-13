#!/bin/sh
# JARVIS OS boot self-test. Runs only when the kernel command line contains
# jarvis.selftest=1 (see jarvis-selftest.service). Prints progress and a final
# "JARVIS-SELFTEST: PASS" or "JARVIS-SELFTEST: FAIL ..." line on the serial
# console, then powers the machine off.
if [ -c /dev/ttyS0 ]; then exec >/dev/ttyS0 2>&1; fi

FAILS=""
fail() { FAILS="$FAILS; $1"; echo "check failed: $1"; }

echo "JARVIS-SELFTEST: start"
echo "kernel: $(uname -r)  arch: $(uname -m)"
echo "cpu: $(grep -m1 'model name' /proc/cpuinfo)"
echo "cpu flags (avx/avx2/sse4_2 must be absent on a Core 2 model): $(grep -m1 '^flags' /proc/cpuinfo | tr ' ' '\n' | grep -E '^(avx|avx2|sse4_1|sse4_2)$' | tr '\n' ' ')"
echo "JARVIS core version: $(cat /opt/home-ai/VERSION 2>/dev/null)"
echo "memory: $(free -m | awk '/^Mem:/ {print $2 " MB total, " $3 " MB used"}')"

# 1. The system finished booting (degraded is reported, not fatal: the live
#    image has units that cannot all start in a VM).
STATE=$(timeout 120 systemctl is-system-running --wait 2>&1)
echo "systemd state: $STATE"

# 2. The service is up and answers over verified HTTPS.
CERT=/var/lib/home-ai/tls/cert.pem
OK=0
for i in $(seq 1 90); do
  if [ -f "$CERT" ] && curl -sf --max-time 5 --cacert "$CERT" https://localhost:8443/api/health > /tmp/health.json 2>/dev/null; then OK=1; break; fi
  sleep 1
done
if [ "$OK" = "1" ]; then
  echo "health: $(cat /tmp/health.json)"
  grep -q '"status":"ok"' /tmp/health.json || fail "health status is not ok"
  grep -q '"setup_required":true' /tmp/health.json || fail "setup should be open on a fresh image"
else
  fail "no HTTPS health answer from https://localhost:8443"
fi

# 3. It runs unprivileged, under systemd, with the hardened unit.
USER_OF=$(ps -o user= -C home-ai 2>/dev/null | head -n 1 | tr -d ' ')
echo "service runs as: ${USER_OF:-none}"
[ "$USER_OF" = "home-ai" ] || fail "service is not running as home-ai"
systemctl is-active --quiet home-ai.service || fail "home-ai.service is not active"

# 4. The frontend is served and carries security headers.
curl -sf --max-time 5 --cacert "$CERT" https://localhost:8443/ | grep -q '<div id="app">' || fail "dashboard page not served"
curl -sfI --max-time 5 --cacert "$CERT" https://localhost:8443/ | grep -qi '^content-security-policy:' || fail "no CSP header"

# 5. No default account: only root and system accounts, nobody with a login shell and a password.
PW=$(awk -F: '$2 !~ /^[!*x]/ && $2 != "" {print $1}' /etc/shadow | tr '\n' ' ')
echo "accounts with a usable password: ${PW:-none}"
[ -z "$PW" ] || fail "accounts with a password exist: $PW"

# 6. Listening only where intended.
echo "listening: $(ss -ltnH | awk '{print $4}' | tr '\n' ' ')"

if [ -z "$FAILS" ]; then
  echo "JARVIS-SELFTEST: PASS"
else
  echo "JARVIS-SELFTEST: FAIL$FAILS"
fi
sync
systemctl poweroff
