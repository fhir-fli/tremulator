#!/usr/bin/env bash
# Log the phone's own per-interface byte counters once a second, so the
# laptop's capture can be checked against what the phone says it sent and
# received. Output results/counters_<label>.tsv: time, iface, rx_bytes, tx_bytes.
#   phone_counters.sh <label> <seconds>
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
label="${1:?label}"; secs="${2:?seconds}"
out="$here/results/counters_$label.tsv"
printf 't\tiface\trx_bytes\ttx_bytes\n' >"$out"
end=$(( $(date +%s) + secs ))
while [ "$(date +%s)" -lt "$end" ]; do
  t=$(date +%T.%3N)
  adb shell cat /proc/net/dev 2>/dev/null | awk -v t="$t" 'NR>2 && ($1 ~ /^(wlan0|rmnet_data[0-9]|rmnet_ipa0):/) {gsub(":","",$1); printf "%s\t%s\t%s\t%s\n", t, $1, $2, $10}' >>"$out"
  sleep 1
done
echo "wrote $out ($(wc -l <"$out") lines)"
