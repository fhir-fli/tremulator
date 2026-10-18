#!/usr/bin/env bash
# E7, header extensions out of audio, repeated (docs/GATE2-CALLS-PLAN.md,
# plan Grey approved 2026-10-18; Grey "go" 2026-10-18 on the repeats).
# calls23 (one run each, P1 relayed on the field link): with abs-send-time
# and transport-cc left out of audio, 28/29 clicks against 15/29, round trip
# 0.9 s against 15 s, no padding. Three rounds, each the control then the
# drop, so drift falls on both alike:
#   <L><n>fc / <L><n>fd  P1 direct and P1 relayed, relay on the field link
#   <L><n>dc / <L><n>dd  P1 relayed, relay on a decent link
# Sound only, speech, Opus 12 kbit/s, 60 ms, DTX, 300 s calls; coded clicks
# (voice_delay.py, 13036c9). The app is calls23's build (unchanged since).
# Stops at the first run that fails. Needs Grey's go (docs/GATE1.md).
#
#     bash lab/gate2/calls_e7_header_repeat.sh calls24
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
run() {
  local label=$1 profiles=$2; shift 2
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles "$profiles" \
    --no-video --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --skip-build "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
DROP=(--audio-drop abs-send-time,transport-cc)
for n in 1 2 3; do
  run "${L}${n}fc" P1,P1-blocked --relay-link field
  run "${L}${n}fd" P1,P1-blocked --relay-link field "${DROP[@]}"
  run "${L}${n}dc" P1-blocked --relay-link decent
  run "${L}${n}dd" P1-blocked --relay-link decent "${DROP[@]}"
done
