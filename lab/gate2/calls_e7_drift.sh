#!/usr/bin/env bash
# E7: how far sound and picture drift apart while video is on, with and
# without --separate-streams (Grey "ok" 2026-10-21). calls29: the option
# ends the held-back voice after video stops on P1; its cost would be drift
# while video runs. P2 and P3, where video stays on all call, direct and
# relayed on the field link; three rounds, each the same build without the
# option (<L><n>s0) then with it (<L><n>s1). Settings as calls29. The
# measure: lip_drift.py, proved by calls_lip_drift_check.sh (7b84f29).
# Prediction: without the option drift stays within about 100 ms (the
# phones sync); with it, drift = voice delay - video delay, unsynced.
#
#     bash lab/gate2/calls_e7_drift.sh calls30
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P2,P2-blocked,P3,P3-blocked \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc --lip-drift \
    --skip-build "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
for n in 1 2 3; do
  run "${L}${n}s0"
  run "${L}${n}s1" --separate-streams
done
