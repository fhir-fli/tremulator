#!/usr/bin/env bash
# E7 third lab pass (docs/GATE2-CALLS-PLAN.md, plan Grey approved
# 2026-10-18): calls start with sound only (VideoGuard.startSending false,
# video after 10 quiet seconds). Everything else as calls19c (Opus asked
# for 12 kbit/s and 60 ms packets, speech, 300 s), so the one change is the
# start: in calls18-19 the video sent before the guard first stopped it
# filled the queue. P1 direct and relayed with the relay on the field link,
# then relayed with the relay on a decent link. The first label rebuilds.
# Stops at the first run that fails. Needs Grey's go (docs/GATE1.md).
#
#     bash lab/gate2/calls_e7_start_sweep.sh calls20
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
run() {
  local label=$1; shift
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --speech \
    --opus-max-bitrate 12000 --opus-ptime 60 "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
run "$L" --profiles P1,P1-blocked
run "${L}d" --profiles P1-blocked --relay-link decent --skip-build
