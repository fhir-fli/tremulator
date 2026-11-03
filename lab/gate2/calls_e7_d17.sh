#!/usr/bin/env bash
# E7: confirm D17 (sound and video as separate streams, the default since
# 2026-11-02; Grey "yes"). Same settings as calls29/31 on P1, three rounds,
# each the same build with one stream (<L><n>s0, --one-stream) then the
# default (<L><n>s1). New: 60 s after a phone's own video stops the lab
# presses "try video again" (--tap-video-after), so the time from a tap to
# the picture back is measured too. Prediction: with separate streams Bob's
# sound playout target falls to what the network needs once video stops, in
# every call; if it stays above it where the one-stream control's does,
# D17's premise is wrong. The first run builds the app (and keeps the server
# image of 2026-10-21 19:28: fhirant #92 refuses the call messages).
#
#     bash lab/gate2/calls_e7_d17.sh calls32
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=()
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1,P1-blocked \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc --lip-drift \
    --tap-video-after 60 --keep-server "${BUILD[@]}" "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  BUILD=(--skip-build)
}
for n in 1 2 3; do
  run "${L}${n}s0" --one-stream
  run "${L}${n}s1"
done
