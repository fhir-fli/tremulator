#!/usr/bin/env bash
# Setup during an outage, three times over (docs/GATE2-CALLS-PLAN.md, plan
# Grey approved 2026-10-17): P4 and the two setup cuts, direct and relayed,
# 300 s calls. The first run rebuilds the app and images; the others reuse
# them. Stops at the first run that fails. Needs Grey's go (docs/GATE1.md).
#
#     bash lab/gate2/calls_setup_sweep.sh calls12 calls13 calls14
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PROFILES=P4,P4-blocked,offercut60,offercut60-blocked,answercut60,answercut60-blocked
build=()
for label in "$@"; do
  python3 "$HERE/calls.py" --label "$label" --profiles "$PROFILES" --call-s 300 "${build[@]}" \
    > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  build=(--skip-build)
done
