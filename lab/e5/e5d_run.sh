#!/usr/bin/env bash
# E5d (docs/GATE2-CALLS-PLAN.md): 60 ms sound packets (--opus-ptime 60)
# against E5c F, the only change. Gate 1's arrangement (only Alice's link
# shaped), three passes of P1-P4 direct and relay-forced, 3-minute calls;
# the app image is E5c F's (same code), so --skip-build. Then the table.
#
#     bash lab/e5/e5d_run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
grep -q '_setVideoActive' packages/tremulator_calls/lib/src/calls.dart || { echo "e5d_run.sh: this tree lacks the video fix"; exit 1; }
P=P1,P2,P3,P4,P1-blocked,P2-blocked,P3-blocked,P4-blocked
code=0
for n in 1 2 3; do
  python3 lab/gate2/calls.py --label "e5d$n" --profiles "$P" --call-s 180 --shape-only alice --opus-ptime 60 --skip-build || code=$?
  echo "e5d_run.sh e5d$n: done (code so far $code)"
done
python3 lab/e5/table.py --name=e5d e5d1 e5d2 e5d3 || code=$?
echo "e5d_run.sh table: done (code $code)"
exit "$code"
