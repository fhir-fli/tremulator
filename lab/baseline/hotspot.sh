#!/usr/bin/env bash
# Host the field phone's Wi-Fi network on this laptop (NetworkManager, no root).
# The hotspot shares the Ethernet uplink by NAT.
#
#   hotspot.sh up        create (first time) and start the access point
#   hotspot.sh down      stop it; the laptop's own Wi-Fi reconnects on its own
#   hotspot.sh online    (re)activate the "Wired" profile on the uplink
#
# There is deliberately NO "offline" command. 2026-10-06: disconnecting the
# uplink cut the laptop's own internet (the Claude session runs over it) and
# NetworkManager then re-attached the port to "pi-direct", a link-local
# profile with no gateway, so the laptop stayed offline for six minutes. The
# no-internet profiles (P5, P0) block the PHONES' traffic with tc in shape.sh
# instead; the laptop keeps its uplink.
#   hotspot.sh status    AP state, its address, phones seen, uplink state
#
# Env: TREM_AP_DEV (wlp2s0), TREM_UPLINK_DEV (enp1s0f0), TREM_AP_BAND (bg|a),
# TREM_AP_SSID (tremulator). The password is generated once into
# results/hotspot.pw (git-ignored).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dev="${TREM_AP_DEV:-wlp2s0}"
uplink="${TREM_UPLINK_DEV:-enp1s0f0}"
band="${TREM_AP_BAND:-bg}"
ssid="${TREM_AP_SSID:-tremulator}"
con="tremulator-ap"
pwfile="$here/results/hotspot.pw"
log="$here/results/hotspot.log"
mkdir -p "$here/results"

note() { printf '%s %s\n' "$(date -Is)" "$*" >>"$log"; echo "$*"; }

case "${1:-}" in
  up)
    if [ ! -s "$pwfile" ]; then
      openssl rand -base64 12 | tr -d '/+=' | cut -c1-12 >"$pwfile"
      chmod 600 "$pwfile"
    fi
    pw="$(cat "$pwfile")"
    if nmcli -t -f NAME connection show | grep -qx "$con"; then
      nmcli connection up "$con"
    else
      nmcli device wifi hotspot ifname "$dev" con-name "$con" ssid "$ssid" \
        band "$band" password "$pw"
    fi
    note "hotspot up: ssid=$ssid band=$band dev=$dev"
    echo "Join SSID '$ssid' with password: $pw"
    ;;
  down)
    nmcli connection down "$con" || true
    note "hotspot down"
    ;;
  online)
    nmcli connection up "${TREM_UPLINK_CON:-Wired}"
    note "uplink profile ${TREM_UPLINK_CON:-Wired} activated on $uplink"
    ;;
  status)
    echo "--- access point $dev"
    nmcli -t -f GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS device show "$dev" || true
    echo "--- stations seen on $dev (ip neigh)"
    ip neigh show dev "$dev" || true
    echo "--- uplink $uplink"
    nmcli -t -f GENERAL.STATE,IP4.ADDRESS device show "$uplink" || true
    echo "--- default route"
    ip route show default || echo "none (offline)"
    echo "--- shaping on $dev"
    tc qdisc show dev "$dev"
    ;;
  *)
    sed -n '2,15p' "$0"; exit 2 ;;
esac
