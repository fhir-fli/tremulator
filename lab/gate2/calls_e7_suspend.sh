#!/usr/bin/env bash
# E7: does Calls.suspendVideoBelowMinimum stop the late voice a "try video
# again" tap costs on a weak relayed link (calls33)? One pair, same settings
# as calls33's tap arm (P1-blocked, field relay, separate streams, tap 60 s
# after each stop): <L>s1 with --suspend-video, then <L>s0 without.
# Method and prediction, fixed before the run (2026-11-09):
# e7_suspend_check.py. e7_tap_cost.py is also run for comparison with
# calls33 (it measures from the first stop, which may not come when video
# is suspended rather than stopped by the guard).
#
#     bash lab/gate2/calls_e7_suspend.sh calls34
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
run "${L}s1" --suspend-video
run "${L}s0" --no-suspend-video
cd "$HERE" && python3 e7_tap_cost.py "results/${L}-tap-cost.jsonl" "${L}s1" "${L}s0"
python3 e7_suspend_check.py "results/${L}-suspend.jsonl" "${L}s1" "${L}s0"
