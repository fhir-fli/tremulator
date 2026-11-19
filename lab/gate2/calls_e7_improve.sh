#!/usr/bin/env bash
# E7: video the engine held back on the weak relayed link, when the link
# gets better. P1-blocked improving to P2 120 s after connect, calls37's
# settings. <L>s1 default (suspend on), <L>s0 --no-suspend-video, <L>nv
# sound only (the voice reference); the first run builds the app.
# Method and decision rule, fixed before the run (2026-11-19): see
# e7_improve_check.py's docstring.
#
#     bash lab/gate2/calls_e7_improve.sh calls38
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=(--keep-server)
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1-blocked \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc --lip-drift \
    --tap-video-after 60 --improve-to P2 --improve-after 120 \
    "${BUILD[@]}" "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  BUILD=(--skip-build --keep-server)
}
run "${L}s1"
run "${L}s0" --no-suspend-video
run "${L}nv" --no-video
cd "$HERE" && python3 e7_improve_check.py "results/${L}-improve.jsonl" "$L"
