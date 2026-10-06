#!/usr/bin/env bash
# Shape the access-point interface to a tremulator profile, both directions,
# with the same netem numbers as the Docker lab (docs/GATE1.md): half the RTT
# and the full loss on each direction's egress, the rate cap on both. Egress
# toward the phone is shaped on the AP interface; the phone's uploads are
# redirected through ifb0 and shaped there. Runs tc inside the lab image on
# the host network with NET_ADMIN, so no sudo is needed.
#
#   shape.sh P1|P2|P3|P5      steady profile
#   shape.sh P0               dead link (100% loss both ways)
#   shape.sh P4               30 s up / 60 s down loop; Ctrl-C leaves the link UP
#   shape.sh off              remove all shaping
#   shape.sh show             current qdiscs
#
# Every change is appended to results/shape.log with a timestamp, so WhatsApp
# events can be placed against the link state.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dev="${TREM_AP_DEV:-wlp2s0}"
ifb="ifb0"
img="tremulator-lab:latest"
log="$here/results/shape.log"
mkdir -p "$here/results"

# profile: rate_kbit rtt_ms loss_pct — SUCCESS.md Gate 1 table
declare -A RATE=([P1]=50 [P2]=300 [P3]=1000 [P4]=300 [P5]=10000)
declare -A RTT=([P1]=400 [P2]=200 [P3]=700 [P4]=250 [P5]=5)
declare -A LOSS=([P1]=5 [P2]=2 [P3]=1 [P4]=2 [P5]=0)

note() { printf '%s %s\n' "$(date -Is)" "$*" >>"$log"; echo "$(date -Is) $*"; }
indocker() { docker run --rm --network host --cap-add NET_ADMIN "$img" sh -c "$1"; }

netem_args() { # rate rtt loss -> netem argument string
  local a="delay $(awk "BEGIN{print $2/2}")ms loss $3%"
  [ "$1" -gt 0 ] && a="$a rate $1kbit"
  echo "$a"
}

ensure_ifb="ip link show $ifb >/dev/null 2>&1 || ip link add $ifb type ifb; ip link set $ifb up;
tc qdisc del dev $dev ingress 2>/dev/null || true;
tc qdisc add dev $dev handle ffff: ingress;
tc filter add dev $dev parent ffff: matchall action mirred egress redirect dev $ifb"

# Declared 2026-10-06 before P3 (after the P1 video call): ARP and DHCP are
# link housekeeping that a cellular link does not have, so they bypass the
# shaping in a fast band of a prio qdisc; everything else goes through netem
# exactly as before. Without this, Android declared the laptop gateway
# unreachable at 50 kbit/s under video load, re-DHCPed, gave up and left for
# the home Wi-Fi mid-call (phone log 10:27:22-10:27:42).
shaped_root() { # dev netem-args -> commands that (re)build prio+netem on dev
  local d="$1" n="$2"
  echo "tc qdisc del dev $d root 2>/dev/null || true;
tc qdisc add dev $d root handle 1: prio bands 2 priomap 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1;
tc filter add dev $d parent 1: protocol arp prio 1 matchall flowid 1:1;
tc filter add dev $d parent 1: protocol ip prio 2 u32 match ip protocol 17 0xff match ip dport 67 0xffff flowid 1:1;
tc filter add dev $d parent 1: protocol ip prio 3 u32 match ip protocol 17 0xff match ip dport 68 0xffff flowid 1:1;
tc qdisc add dev $d parent 1:2 handle 20: netem $n"
}
set_netem() { # dev netem-args -> replace only the netem leaf (keeps the fast band)
  echo "tc qdisc replace dev $1 parent 1:2 handle 20: netem $2"
}

apply() { # netem argument string; full rebuild
  indocker "$ensure_ifb;
$(shaped_root "$dev" "$1");
$(shaped_root "$ifb" "$1")"
}
retune() { # netem argument string; leaf only (P4 toggling)
  indocker "$(set_netem "$dev" "$1"); $(set_netem "$ifb" "$1")"
}

# P5 is a LAN with no way out. The LAPTOP keeps its uplink (the session runs
# over it; 2026-10-06). The phones' traffic to anything outside 10.42.0.0/24,
# and their DNS to the laptop, is dropped by tc filters; LAN traffic between
# the phones and to the laptop passes, shaped as the profile says.
noinet_filters() { # dev -> filters that let LAN through and drop the rest
  echo "tc filter add dev $1 parent 1: protocol ip prio 4 u32 match ip dst 10.42.0.1/32 match ip protocol 17 0xff match ip dport 53 0xffff action drop;
tc filter add dev $1 parent 1: protocol ip prio 5 u32 match ip dst 10.42.0.0/24 flowid 1:2;
tc filter add dev $1 parent 1: protocol ip prio 6 u32 match ip src 0.0.0.0/0 action drop"
}

p="${1:-}"
case "$p" in
  P1|P2|P3)
    apply "$(netem_args "${RATE[$p]}" "${RTT[$p]}" "${LOSS[$p]}")"
    note "shape $p on $dev: rate ${RATE[$p]} kbit/s rtt ${RTT[$p]} ms loss ${LOSS[$p]}% both directions"
    ;;
  P5)
    apply "$(netem_args "${RATE[P5]}" "${RTT[P5]}" "${LOSS[P5]}")"
    indocker "$(noinet_filters "$dev"); $(noinet_filters "$ifb")"
    note "shape P5 on $dev: rate ${RATE[P5]} kbit/s rtt ${RTT[P5]} ms loss 0%; phones' non-LAN traffic and DNS dropped (laptop uplink untouched)"
    ;;
  P0)
    apply "loss 100%"
    note "shape P0 on $dev: dead link, 100% loss both directions"
    ;;
  P4)
    up="$(netem_args "${RATE[P4]}" "${RTT[P4]}" "${LOSS[P4]}")"
    apply "$up"
    note "shape P4 on $dev: duty loop start (30 s up / 60 s down); up = $up"
    trap 'echo; note "shape P4: loop stopped by user; link left UP"; exit 0' INT TERM
    while true; do
      note "P4 up"
      sleep 30
      retune "loss 100%"
      note "P4 down"
      sleep 60
      retune "$up"
    done
    ;;
  off)
    indocker "tc qdisc del dev $dev root 2>/dev/null || true;
tc qdisc del dev $dev ingress 2>/dev/null || true;
ip link del $ifb 2>/dev/null || true"
    note "shape off on $dev"
    ;;
  show)
    tc qdisc show dev "$dev"; tc filter show dev "$dev" parent 1: | grep -c flowid | sed 's/^/fast-lane filters: /'
    tc qdisc show dev "$ifb" 2>/dev/null || echo "no $ifb"
    ;;
  *)
    sed -n '2,16p' "$0"; exit 2 ;;
esac
