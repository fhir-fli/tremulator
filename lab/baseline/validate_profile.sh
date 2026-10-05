#!/usr/bin/env bash
# Run baseline_validate for one profile with the phone side driven over adb:
# every "iperf3 -c ..." command the validator asks for is typed into Termux.
# Output: results/validate_<label>.jsonl (the validator's) and
# results/validate_<label>_<profile>.out (its console).
#   validate_profile.sh <profile> <phone-ip> <label> <base-rtt-ms> [extra validator args]
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
profile="${1:?profile}"; phone="${2:?phone ip}"; label="${3:?label}"; base="${4:?base rtt}"
shift 4
out="$here/results/validate_${label}_${profile}.out"
: >"$out"
( cd "$here/../tool" && dart run bin/baseline_validate.dart --profile "$profile" \
    --phone "$phone" --label "$label" --base-rtt "$base" "$@" >>"$out" 2>&1 ) &
vpid=$!
echo "validator pid $vpid, console $out"
sent=0
phonefile=""
stop_run() { # kill the one-shot server so the validator records an error and retries
  docker ps -q --filter ancestor=tremulator-lab:latest | xargs -r docker kill >/dev/null 2>&1
}
while kill -0 "$vpid" 2>/dev/null; do
  ip=$(adb shell ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)
  case "$ip" in
    10.42.*) ;;
    *) echo "$(date -Is) PHONE LEFT THE HOTSPOT (wlan0=$ip); aborting validation"
       kill "$vpid" 2>/dev/null; stop_run; wait "$vpid" 2>/dev/null; exit 3 ;;
  esac
  n=$(grep -c '^    iperf3 -c' "$out")
  if [ "$n" -gt "$sent" ]; then
    cmd=$(grep '^    iperf3 -c' "$out" | sed -n "$((sent+1))p" | sed 's/^    //')
    sleep 2   # let the one-shot server come up
    phonefile="trem_${label}_${profile}_$n.txt"
    adb shell rm -f "/sdcard/Download/$phonefile"
    "$here/termux.sh" "$cmd" "$phonefile" >/dev/null 2>&1
    echo "$(date -Is) typed into Termux: $cmd  (phone output $phonefile)"
    sent=$n
  fi
  if [ -n "$phonefile" ] && adb shell grep -q 'iperf3: error' "/sdcard/Download/$phonefile" 2>/dev/null; then
    echo "$(date -Is) phone reported: $(adb shell grep 'iperf3: error' "/sdcard/Download/$phonefile" | head -1)"
    adb shell cat "/sdcard/Download/$phonefile" > "$here/results/${phonefile%.txt}.phone.txt"
    phonefile=""
    stop_run
  fi
  sleep 1
done
adb shell "ls /sdcard/Download/trem_${label}_${profile}_*.txt 2>/dev/null" | while read -r f; do
  adb shell cat "$f" > "$here/results/$(basename "${f%.txt}").phone.txt"
done
wait "$vpid"; code=$?
echo "validator exit $code"
grep '"metric"' "$out" | sed 's/^Running build hooks\.\.\.//'
exit $code
