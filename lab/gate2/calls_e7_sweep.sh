#!/usr/bin/env bash
# E7 first lab pass (docs/GATE2-CALLS-PLAN.md, plan Grey approved
# 2026-10-18): the video guard on P1 with speech, direct, relayed with the
# relay on the field link, and relayed with the relay on a decent link; an
# unslowed control with speech and one with clicks only (calls17 read 233 ms
# with speech against calls9's 103 ms with clicks, on different builds).
# 300 s calls. The first label rebuilds the app and images. Stops at the
# first run that fails. Needs Grey's go (docs/GATE1.md).
#
#     bash lab/gate2/calls_e7_sweep.sh calls18
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
run "$L" --profiles none,P1,P1-blocked --speech
run "${L}d" --profiles P1-blocked --speech --relay-link decent --skip-build
run "${L}c" --profiles none --skip-build
