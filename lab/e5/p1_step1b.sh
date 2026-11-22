#!/usr/bin/env bash
# E5 follow-up step 1b (docs/GATE2-CALLS-PLAN.md): P1 and P1-blocked with no
# video stream (--no-video) and 60 ms sound packets (--opus-ptime 60), three passes, 3-minute calls, nothing else
# changed; then p1_step1.py judges them.
#
#     bash lab/e5/p1_step1.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
code=0
for n in 1 2 3; do
  python3 lab/gate2/calls.py --label "e5p60_$n" --profiles P1,P1-blocked --call-s 180 --no-video --opus-ptime 60 --skip-build || code=$?
  echo "p1_step1b.sh e5p60_$n: done (code so far $code)"
done
python3 lab/e5/p1_step1.py --out=p1_step1b.jsonl e5p60_1 e5p60_2 e5p60_3 || code=$?
echo "p1_step1.sh judged (code $code)"
exit "$code"
