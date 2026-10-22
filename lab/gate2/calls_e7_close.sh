#!/usr/bin/env bash
# E7: the second fix for the held-back voice (Grey "ok" 2026-10-21). calls29
# P1: with video in one stream with the sound, Bob's playout target stayed at
# 558-1,154 ms after video stopped in 4 of 6 calls (network needed 40-80 ms);
# --separate-streams ended it in 6 of 6. --close-stopped-video keeps them in
# one stream, but when video stops the phones agree, with a new offer, that
# it is off (Calls.closeStoppedVideo). Prediction: the target falls to what
# the network needs once video stops. If it stays near 1,000 ms in calls
# where the control's does, the fix fails. Three rounds, each the same build
# without (<L><n>c0) then with it (<L><n>c1); settings as calls29, plus the
# lip-drift flash. The first run builds the app; --keep-server keeps the
# server image of 2026-10-21 19:28 (calls.py build: fhirant #92 refuses the
# call messages).
#
#     bash lab/gate2/calls_e7_close.sh calls31
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=()
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1,P1-blocked \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc --lip-drift \
    --keep-server "${BUILD[@]}" "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  BUILD=(--skip-build)
}
for n in 1 2 3; do
  run "${L}${n}c0"
  run "${L}${n}c1" --close-stopped-video
done
