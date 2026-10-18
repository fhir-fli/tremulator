#!/usr/bin/env bash
# E7, sound overhead on the relay's 50 kbit/s link (docs/GATE2-CALLS-PLAN.md,
# plan Grey approved 2026-10-18). calls22: the silent phone padded its sound
# stream, 148 kB of the 596 kB it sent, with 99 and 111 padding packets in
# the call's first two seconds; padding needs the send time and congestion
# feedback header extensions. Hypothesis: with both left out of the audio
# section (RFC 8285 section 7), the padding stops, each packet's header falls
# from 28 to about 20 bytes, and more clicks are heard.
#   a  calls22's settings again, this build (the control)
#   b  the same, with abs-send-time and transport-cc left out of audio
# P1 with the relay on the field link, sound only, speech, Opus 12 kbit/s,
# 60 ms, DTX, 300 s calls. The first label rebuilds the app.
# Stops at the first run that fails. Needs Grey's go (docs/GATE1.md).
#
#     bash lab/gate2/calls_e7_header_sweep.sh calls23
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1-blocked \
    --no-video --speech --relay-link field \
    --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx "$@" \
    > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
run "${L}a"
run "${L}b" --audio-drop abs-send-time,transport-cc --skip-build
