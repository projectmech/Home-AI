#!/bin/bash
# Network screens shared by the installer setup (jarvis-setup) and the first-start setup
# (jarvis-firstboot). Sourced, not run. The caller defines T (whiptail that prints its
# answer on stdout), msg (a message box), BT (the back title) and the variables
# NETMODE and NETINFO, which wifi_flow sets when it joins a network.
ipv4_of() { ip -4 -o addr show dev "$1" scope global 2>/dev/null | awk '{sub(/\/.*/, "", $4); print $4; exit}'; }
wifi_if() {
  local d n
  for d in /sys/class/net/*; do
    n=$(basename "$d")
    case "$n" in wl* | wlan*) printf '%s' "$n"; return ;; esac
  done
}
wired_ip() {
  local d n ip
  for d in /sys/class/net/e*; do
    n=$(basename "$d")
    ip=$(ipv4_of "$n")
    [ -n "$ip" ] && { printf '%s' "$ip"; return; }
  done
}

wifi_flow() {
  local ifw list line ssid pw i n sig opt
  ifw=$(wifi_if)
  if [ -z "$ifw" ]; then
    modprobe wl > /dev/null 2>&1 || true
    sleep 2
    ifw=$(wifi_if)
  fi
  if [ -z "$ifw" ]; then
    local diag
    diag=$(dmesg 2>/dev/null | grep -iE 'wl|brcm|b43|bcma|4331|cfg80211' | tail -n 5 | cut -c1-66)
    msg "No Wi-Fi adapter was found.\n\nThe Mac mini's Wi-Fi chip (Broadcom BCM4331) needs a driver that is part of this installer, so the adapter did not start. Please tell the developer what follows:\n\n${diag:-(no messages about the Wi-Fi chip)}\n\nYou can go Back and use the Ethernet cable, or skip the network and set it up later." "Wi-Fi" 20
    return 1
  fi
  rfkill unblock wifi > /dev/null 2>&1 || true
  ip link set "$ifw" up > /dev/null 2>&1 || true
  while :; do
    whiptail --backtitle "$BT" --title "Wi-Fi" --infobox "Looking for Wi-Fi networks..." 6 50
    list=$(iw dev "$ifw" scan 2>/dev/null | awk '
      /^BSS / { if (ssid != "") print sig "\t" ssid; ssid = ""; sig = -100 }
      /signal:/ { sig = $2 }
      /SSID:/ { sub(/^[ \t]*SSID: /, ""); ssid = $0 }
      END { if (ssid != "") print sig "\t" ssid }' | sort -t"$(printf '\t')" -k1,1nr | awk -F'\t' 'length($2) > 0 && !seen[$2]++' | head -n 12)
    local -a names=() menu=()
    i=0
    while IFS=$'\t' read -r sig ssid; do
      [ -n "$ssid" ] || continue
      names+=("$ssid")
      i=$((i + 1))
      menu+=("$i" "$ssid   (signal ${sig%.*} dBm)")
    done <<< "$list"
    menu+=("other" "A network that is not listed (type its name)")
    menu+=("rescan" "Look again")
    opt=$(T --title "Wi-Fi" --ok-button "Choose" --cancel-button "Back" \
      --menu "Choose your Wi-Fi network." 20 70 12 "${menu[@]}") || return 1
    case "$opt" in
      rescan) continue ;;
      other) ssid=$(T --title "Wi-Fi" --inputbox "Network name:" 8 60 "") || continue ;;
      *) n=$((opt - 1)); ssid=${names[$n]} ;;
    esac
    [ -n "$ssid" ] || continue
    pw=$(T --title "Wi-Fi: $ssid" --passwordbox "Password for \"$ssid\".\n(Leave empty for an open network.)" 10 64 "") || continue
    whiptail --backtitle "$BT" --title "Wi-Fi" --infobox "Connecting to \"$ssid\"..." 6 60
    JARVIS_WIFI_PASS="$pw" jarvis-wifi connect "$ssid" > /dev/null 2>&1 || true
    local t=0 ip=""
    while [ "$t" -lt 30 ]; do
      ip=$(ipv4_of "$ifw")
      [ -n "$ip" ] && break
      sleep 1
      t=$((t + 1))
    done
    if [ -n "$ip" ]; then
      NETMODE=wifi
      NETINFO="Wi-Fi \"$ssid\" ($ip)"
      msg "Connected to \"$ssid\".\n\nThis computer's address: $ip" "Wi-Fi" 9
      return 0
    fi
    msg "Could not connect to \"$ssid\".\n\nCheck the password and that the network is in range, then try again." "Wi-Fi" 10
  done
}
