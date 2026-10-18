#!/usr/bin/env bash
# E7 second lab pass (docs/GATE2-CALLS-PLAN.md, plan Grey approved
# 2026-10-18): sound made to fit P1. calls18 P1 with speech: video stopped,
# yet Opus kept its 32 kbit/s target (about 48 kbit/s with headers on a
# 50 kbit/s link) and 14 of 29 clicks were heard. One change at a time, each
# both phones asking (RFC 7587 receive parameters):
#   a  maxaveragebitrate 16000 (the low end of wideband speech, RFC 7587
#      section 3.1.1: 16-20 kbit/s)
#   b  the same, and ptime 60 (fewer packets, so fewer headers; section 5)
#   c  maxaveragebitrate 12000 and ptime 60 (between narrowband's 8-12 and
#      wideband's 16)
# P1 direct and relayed with the relay on the field link (the harder case),
# speech, video guard on, 300 s calls. The first label rebuilds the app (the
# guard's route fix after calls18); the others reuse it.
# Stops at the first run that fails. Needs Grey's go (docs/GATE1.md).
#
#     bash lab/gate2/calls_e7_opus_sweep.sh calls19
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles P1,P1-blocked \
    --speech "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
run "${L}a" --opus-max-bitrate 16000
run "${L}b" --opus-max-bitrate 16000 --opus-ptime 60 --skip-build
run "${L}c" --opus-max-bitrate 12000 --opus-ptime 60 --skip-build
