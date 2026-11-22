#!/usr/bin/env bash
# E5: three passes of every profile, 3-minute video calls, shipped defaults
# (docs/GATE2-CALLS-PLAN.md, E5 plan), then the table (table.py).
#
#     bash lab/e5/run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
P=P1,P2,P3,P4,P5,P0,P1-blocked,P2-blocked,P3-blocked
code=0
for n in 1 2 3; do
  skip=""; [ "$n" != 1 ] && skip="--skip-build"
  python3 lab/gate2/calls.py --label "e5r$n" --profiles "$P" --call-s 180 $skip || code=$?
  echo "run.sh e5r$n: done (code so far $code)"
done
python3 lab/e5/table.py e5r1 e5r2 e5r3 || code=$?
echo "run.sh table: done (code $code)"
exit "$code"
