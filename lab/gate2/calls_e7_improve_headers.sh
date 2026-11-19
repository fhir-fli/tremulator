#!/usr/bin/env bash
# E7: calls39s1 again with ONE change: no --audio-drop, so the sound keeps
# its abs-send-time and transport-cc header fields, as the shipped app does
# (Calls.audioExtensions drops nothing by default). P1-blocked improving to
# P2 120 s after connect, otherwise calls39's settings. Reuses the phone
# image of 2026-11-09 17:38 (INVALID-RUNS calls38).
# Hypothesis and prediction, fixed before the run (2026-11-19): in calls39s1
# Alice's link estimate stayed 5-10 kbit/s on a 300 kbit/s link and held
# video never came back. If that is because the estimate got feedback only
# from video packets while video was held, then with the sound's fields kept
# her estimate rises after the switch and video comes back without a tap
# (e7_improve_check.py: resume_notice_s not null, resume_frames_s not null).
# If video still stays held, the header drop is not the cause.
# The voice is compared with calls39nv, which dropped the fields: a second
# difference, so that comparison is a guide only.
#
#     bash lab/gate2/calls_e7_improve_headers.sh calls40
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
python3 "$HERE/calls.py" --label "${L}s1" --call-s 300 --profiles P1-blocked \
  --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
  --relay-link field --lip-drift \
  --tap-video-after 60 --improve-to P2 --improve-after 120 \
  --skip-build --keep-server > "$HERE/results/${L}s1.out" 2>&1
echo "${L}s1 exit 0" >> "$HERE/results/${L}s1.out"
cd "$HERE" && python3 e7_improve_check.py "results/${L}-improve.jsonl" "$L" \
  s1="${L}s1" nv=calls39nv
