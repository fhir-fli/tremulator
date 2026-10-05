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

apply() { # netem argument string
  indocker "$ensure_ifb;
tc qdisc replace dev $dev root netem $1;
tc qdisc replace dev $ifb root netem $1"
}

p="${1:-}"
case "$p" in
  P1|P2|P3|P5)
    apply "$(netem_args "${RATE[$p]}" "${RTT[$p]}" "${LOSS[$p]}")"
    note "shape $p on $dev: rate ${RATE[$p]} kbit/s rtt ${RTT[$p]} ms loss ${LOSS[$p]}% both directions"
    if [ "$p" = P5 ] && ip route show default | grep -q .; then
      echo "WARNING: P5 requires no internet route; run hotspot.sh offline" >&2
    fi
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
      indocker "tc qdisc replace dev $dev root netem loss 100%; tc qdisc replace dev $ifb root netem loss 100%"
      note "P4 down"
      sleep 60
      apply "$up"
    done
    ;;
  off)
    indocker "tc qdisc del dev $dev root 2>/dev/null || true;
tc qdisc del dev $dev ingress 2>/dev/null || true;
ip link del $ifb 2>/dev/null || true"
    note "shape off on $dev"
    ;;
  show)
    tc qdisc show dev "$dev"; tc qdisc show dev "$ifb" 2>/dev/null || echo "no $ifb"
    ;;
  *)
    sed -n '2,16p' "$0"; exit 2 ;;
esac
