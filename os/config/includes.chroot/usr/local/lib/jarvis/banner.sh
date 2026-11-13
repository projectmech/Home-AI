#!/bin/sh
# Shows how to reach this JARVIS OS live image: on the screen (tty1), on the
# serial console if there is one, and in the login banner (/etc/issue.d).
# Runs once per boot, before the login prompts, and waits up to 90 seconds for
# the network and the service. Nothing here is logged to the journal: the
# output of this unit is discarded because it contains the setup token.

ISSUE=/etc/issue.d/20-jarvis.issue
mkdir -p /etc/issue.d

ipv4() { ip -4 -o addr show scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4; exit}'; }
healthy() { curl -sf --max-time 3 --cacert /var/lib/home-ai/tls/cert.pem https://localhost:8443/api/health >/dev/null 2>&1; }

i=0
while [ "$i" -lt 90 ]; do
  if healthy && [ -n "$(ipv4)" ]; then break; fi
  i=$((i + 1)); sleep 1
done

IP=$(ipv4)
HOSTNAME_NOW=$(hostname)
FP=$(/usr/local/bin/home-ai tls-fingerprint 2>/dev/null)
TOKEN=$(/usr/local/bin/home-ai setup-token 2>/dev/null | grep -Eo '[0-9a-f]{64}' | head -n 1)
[ -n "$IP" ] || IP="(no address yet - is the network cable plugged in?)"
[ -n "$TOKEN" ] || TOKEN="(none - setup is already complete)"
[ -n "$FP" ] || FP="(unavailable)"

TEXT=$(cat <<EOF

==============================================================================
 JARVIS OS - live test image. Nothing is installed on this computer's disk.
==============================================================================
 Open this on another computer on the same network:

 Dashboard:   https://$IP:8443
 Alternative: https://$HOSTNAME_NOW.local:8443

 Setup token: $TOKEN
              (valid for 60 minutes; restart this computer for a new one)

 Certificate SHA-256: $FP

 The certificate is self-signed, so the browser will warn. Compare the
 fingerprint in the browser's warning with the one above, and continue only
 if they are identical.

 Everything you set up is kept in memory only and is lost at power-off.
==============================================================================

EOF
)

printf '%s\n' "$TEXT" > "$ISSUE"
printf '%s\n' "$TEXT" > /dev/tty1 2>/dev/null
if [ -c /dev/ttyS0 ]; then printf '%s\n' "$TEXT" > /dev/ttyS0 2>/dev/null; fi
exit 0
