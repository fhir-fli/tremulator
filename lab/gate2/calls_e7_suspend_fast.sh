#!/usr/bin/env bash
# E7: with Calls.suspendVideoBelowMinimum, does video still come on over
# the faster links? calls34 (P1-blocked) encoded no video at all with it.
# Same settings as calls34, profiles P2 and P3 (direct): <L>s1 with
# --suspend-video, <L>s0 without.
# Method and prediction, fixed before the run (2026-11-09), read from
# e7_suspend_check.py's columns: with the option, on both P2 and P3,
# Alice encodes video frames (frames_encoded > 0) and Bob decodes them
# (bob_frames_decoded > 0). Also compared, not predicted: voice median and
# max, playout target, frames with and without.
#
#     bash lab/gate2/calls_e7_suspend_fast.sh calls35
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=(--skip-build --keep-server)
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P2,P3 \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc --lip-drift \
    --tap-video-after 60 "${BUILD[@]}" "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
run "${L}s1" --suspend-video
run "${L}s0"
cd "$HERE" && python3 e7_suspend_check.py "results/${L}-suspend.jsonl" "${L}s1" "${L}s0"
