#!/bin/sh
# Shows how to reach this JARVIS OS live image: on the screen (tty1), on the
# serial console if there is one, and in the login banner (/etc/issue.d).
# Runs once per boot, before the login prompts, and waits up to 90 seconds for
# the network and the service. Nothing here is logged to the journal: the
# output of this unit is discarded because it contains the setup token.

ISSUE=/etc/issue.d/20-jarvis.issue
mkdir -p /etc/issue.d

# Diagnostics for the kernel log (visible on the serial console and in dmesg).
# Lengths and states only: never the token or anything secret.
sysctl -q -w kernel.printk_devkmsg=on 2>/dev/null
dbg() { printf 'jarvis-banner: %s\n' "$*" > /dev/kmsg 2>/dev/null; }
dbg "started"

ipv4() { ip -4 -o addr show scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4; exit}'; }
healthy() { curl -sf --max-time 3 --cacert /var/lib/home-ai/tls/cert.pem https://localhost:8443/api/health >/dev/null 2>&1; }

# The first-start setup (jarvis-firstboot) runs this again when it finishes, with
# JARVIS_BANNER_WAIT set to a few seconds, and then the login screen is cleared first.
i=0
while [ "$i" -lt "${JARVIS_BANNER_WAIT:-90}" ]; do
  if healthy && [ -n "$(ipv4)" ]; then break; fi
  i=$((i + 1)); sleep 1
done

IP=$(ipv4)
HOSTNAME_NOW=$(hostname)
FP=$(/usr/local/bin/home-ai tls-fingerprint 2>/dev/null)
TOKEN=$(/usr/local/bin/home-ai setup-token 2>/dev/null | grep -Eo '[0-9a-f]{64}' | head -n 1)
dbg "waited ${i}s healthy=$(healthy && echo yes || echo no) ip=${IP:-none} token_len=${#TOKEN} fp_len=${#FP} tty1=$([ -c /dev/tty1 ] && echo yes || echo no) ttyS0=$([ -c /dev/ttyS0 ] && echo yes || echo no)"
# Display state, for diagnosing the boot screen (states only, nothing secret).
dbg "display: fb0=$([ -c /dev/fb0 ] && echo yes || echo no) dri=$(ls /dev/dri 2>/dev/null | tr '\n' ',') splash_arg=$(grep -qw splash /proc/cmdline && echo yes || echo no) plymouthd=$(pgrep -x plymouthd >/dev/null 2>&1 && echo running || echo not-running)"
dmesg 2>/dev/null | grep -iE 'simpledrm|efifb|fb0|plymouth|framebuffer|drm' | head -n 8 | while IFS= read -r l; do dbg "dmesg: $l"; done
# Plymouth's own debug log (only exists when started with plymouth.debug).
if [ -r /var/log/plymouth-debug.log ]; then
  dbg "plog: lines=$(wc -l < /var/log/plymouth-debug.log)"
  grep -iE 'script|jarvis|png|image' /var/log/plymouth-debug.log | grep -vE 'ThemeDir|plymouthd.defaults' | head -n 12 | while IFS= read -r l; do dbg "plog-script: $(printf '%s' "$l" | cut -c1-230)"; done
  grep -iE 'device-manager|renderer|fb0|serial|ignore|splash plugin|falling|xkb|keyboard' /var/log/plymouth-debug.log | grep -vE 'ThemeDir|plymouthd.defaults' | head -n 14 | while IFS= read -r l; do dbg "plog-script: $(printf '%s' "$l" | cut -c1-230)"; done
  tail -n 22 /var/log/plymouth-debug.log | while IFS= read -r l; do dbg "plog-tail: $(printf '%s' "$l" | cut -c1-230)"; done
fi
journalctl -b -u plymouth-start.service --no-pager 2>/dev/null | tail -n 4 | while IFS= read -r l; do dbg "plog: unit: $l"; done
[ -n "$IP" ] || IP="(no address yet - is the network cable plugged in?)"
[ -n "$TOKEN" ] || TOKEN="(none - setup is already complete)"
[ -n "$FP" ] || FP="(unavailable)"

# What the hardware reports, so a missing network can be diagnosed from the
# screen: each interface with its kernel driver and whether a cable is seen.
NETINFO=""
for d in /sys/class/net/*; do
  n=${d##*/}
  [ "$n" = "lo" ] && continue
  drv=$(basename "$(readlink "$d/device/driver" 2>/dev/null)" 2>/dev/null)
  [ -n "$drv" ] || drv="unknown"
  st=$(cat "$d/operstate" 2>/dev/null)
  if [ "$(cat "$d/carrier" 2>/dev/null)" = "1" ]; then link="cable connected"; else link="NO LINK (cable?)"; fi
  NETINFO="$NETINFO
 Network:     $n  driver=$drv  state=${st:-?}  $link"
done
[ -n "$NETINFO" ] || NETINFO="
 Network:     NO NETWORK INTERFACE FOUND"
# The network chips the computer has, wired and wireless, with their PCI ids
# (vendor:device), whether or not any driver claimed them.
lspci -nn 2>/dev/null | grep -iE 'ethernet|network' | sed 's/^[^ ]* //' > /tmp/pci-net.txt
while IFS= read -r line; do
  NETINFO="$NETINFO
 Hardware:    $line"
done < /tmp/pci-net.txt
rm -f /tmp/pci-net.txt
dbg "net:$(printf '%s' "$NETINFO" | tr '\n' ' ')"

if [ -d /run/live ]; then
  TITLE="JARVIS OS - live test image. Nothing is installed on this computer's disk."
  NOTE="Everything you set up is kept in memory only and is lost at power-off."
else
  TITLE="JARVIS OS"
  NOTE="Your data is kept on this computer's encrypted disk."
fi

TEXT=$(cat <<EOF

==============================================================================
 $TITLE
==============================================================================
 Open this on another computer on the same network:

 Dashboard:   https://$IP:8443
 Alternative: https://$HOSTNAME_NOW.local:8443$NETINFO

 Setup token: $TOKEN
              (valid for 60 minutes; restart this computer for a new one)

 Certificate SHA-256: $FP

 The certificate is self-signed, so the browser will warn. Compare the
 fingerprint in the browser's warning with the one above, and continue only
 if they are identical.

 $NOTE
==============================================================================

EOF
)

printf '%s\n' "$TEXT" > "$ISSUE"
if [ -n "${JARVIS_BANNER_WAIT:-}" ]; then printf '\033[2J\033[H' > /dev/tty1 2>/dev/null; fi
printf '%s\n' "$TEXT" > /dev/tty1 2>/dev/null
if [ -c /dev/ttyS0 ]; then printf '%s\n' "$TEXT" > /dev/ttyS0 2>/dev/null; fi
exit 0
