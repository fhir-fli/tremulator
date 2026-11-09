#!/usr/bin/env bash
# E7: the default build (suspend on, held notice) on the weak relayed link,
# against --no-suspend-video. Same settings as calls34. <L>s1 default,
# <L>s0 --no-suspend-video; the first run builds the app.
# Method and prediction, fixed before the run (2026-11-09), read from
# e7_suspend_check.py's columns: in <L>s1 Alice reports her video held
# (alice_held_s not null, within 10 s of video start) and Bob is told
# (bob_told_held true); and <L>s1's playout target is more than 300 ms
# below <L>s0's (calls34 repeated).
#
#     bash lab/gate2/calls_e7_held.sh calls36
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=(--keep-server)
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1-blocked \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc --lip-drift \
    --tap-video-after 60 "${BUILD[@]}" "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  BUILD=(--skip-build --keep-server)
}
run "${L}s1"
run "${L}s0" --no-suspend-video
cd "$HERE" && python3 e7_suspend_check.py "results/${L}-suspend.jsonl" "${L}s1" "${L}s0"
