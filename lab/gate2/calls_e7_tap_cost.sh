#!/usr/bin/env bash
# E7: what a "try video again" tap costs in late voice on a weak relayed
# link (D17's open point). Same settings as calls32, P1-blocked only,
# separate streams (the default), three rounds, each the same build with the
# lab tapping 60 s after each video stop (<L><n>t1) then nobody tapping
# (<L><n>t0). Method and prediction: e7_tap_cost.py. The first run builds
# the app; the server image is built first by labkit.build_server()
# (fhirant main, which accepts message/mls).
#
#     bash lab/gate2/calls_e7_tap_cost.sh calls33
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=(--keep-server)
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1-blocked \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc --lip-drift \
    "${BUILD[@]}" "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  BUILD=(--skip-build --keep-server)
}
for n in 1 2 3; do
  run "${L}${n}t1" --tap-video-after 60
  run "${L}${n}t0"
done
cd "$HERE" && python3 e7_tap_cost.py "results/${L}-tap-cost.jsonl" \
  "${L}1t1" "${L}1t0" "${L}2t1" "${L}2t0" "${L}3t1" "${L}3t0"
