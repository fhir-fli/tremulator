#!/usr/bin/env bash
# E7: is it lip sync that holds the sound back after video stops? (Grey
# "go" 2026-10-21.) calls28 P1 with abs-send-time and transport-cc dropped:
# after video started and stopped, Bob's sound playout aimed at 850-1,550 ms
# to the end of the call while the network needed 40-100 ms, in all 6 calls.
# Prediction if lip sync: with the video in a stream of its own
# (--separate-streams, 784f651) the aim falls to what the network needs once
# video stops. If it stays near 1,000 ms, lip sync is not the cause.
# Three rounds, each the same build without the flag (<L><n>s0) then with it
# (<L><n>s1), P1 direct and relayed on the field link, so the build is not a
# second variable. Video, speech, Opus 12 kbit/s, 60 ms, DTX, 300 s calls.
# The first run builds the app. Stops at the first run that fails.
#
#     bash lab/gate2/calls_e7_lipsync.sh calls29
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=()
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1,P1-blocked \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --relay-link field --audio-drop abs-send-time,transport-cc \
    "${BUILD[@]}" "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  BUILD=(--skip-build)
}
for n in 1 2 3; do
  run "${L}${n}s0"
  run "${L}${n}s1" --separate-streams
done
