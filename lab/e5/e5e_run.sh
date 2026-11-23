#!/usr/bin/env bash
# E5e (docs/GATE2-CALLS-PLAN.md): video never paused,
# with --no-suspend-video against E5d, the only change (video at its lowest
# rate, never paused by the engine; lab/e5/P1-VIDEO.md). Gate 1's arrangement (only Alice's link
# shaped), three passes of P1-P4 direct and relay-forced, 3-minute calls;
# the app image is E5d's (same code), so --skip-build. Then the table.
#
#     bash lab/e5/e5e_run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
grep -q '_setVideoActive' packages/tremulator_calls/lib/src/calls.dart || { echo "e5e_run.sh: this tree lacks the video fix"; exit 1; }
P=P1,P2,P3,P4,P1-blocked,P2-blocked,P3-blocked,P4-blocked
code=0
for n in 1 2 3; do
  python3 lab/gate2/calls.py --label "e5e$n" --profiles "$P" --call-s 180 --shape-only alice --opus-ptime 60 --no-suspend-video --skip-build || code=$?
  echo "e5e_run.sh e5e$n: done (code so far $code)"
done
python3 lab/e5/table.py --name=e5e e5e1 e5e2 e5e3 || code=$?
echo "e5e_run.sh table: done (code $code)"
exit "$code"
