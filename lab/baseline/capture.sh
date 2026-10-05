#!/usr/bin/env bash
# Capture the field phone's traffic on the access-point interface. Headers
# only (160 bytes per packet): WhatsApp is encrypted, we want timing, sizes and
# endpoints. The file is results/<label>.pcap, written by tcpdump through its
# stdout so it belongs to you, not root. Ctrl-C stops it. Analyse with
# `dart run lab/tool/bin/baseline_flows.dart results/<label>.pcap`.
#
#   capture.sh <label>
#
# Optional: audio_delay.sh records the laptop microphone for the clap test.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dev="${TREM_AP_DEV:-wlp2s0}"
img="tremulator-lab:latest"
label="${1:?label}"
case "$label" in -*) echo "label must not start with -" >&2; exit 2;; esac
out="$here/results/$label.pcap"
log="$here/results/capture.log"
mkdir -p "$here/results"
[ -e "$out" ] && { echo "$out exists; pick another label" >&2; exit 2; }
printf '%s start %s\n' "$(date -Is)" "$label" >>"$log"
echo "capturing $dev -> $out (Ctrl-C to stop)"
trap 'printf "%s stop %s %s bytes\n" "$(date -Is)" "$label" "$(stat -c %s "$out")" >>"$log"' EXIT
docker run --rm --network host "$img" tcpdump -i "$dev" -nn -U -s 160 -w - >"$out"
