#!/usr/bin/env bash
# E5 follow-up step 1 (docs/GATE2-CALLS-PLAN.md): P1 and P1-blocked with no
# video stream (--no-video), three passes, 3-minute calls, nothing else
# changed; then p1_step1.py judges them.
#
#     bash lab/e5/p1_step1.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
code=0
for n in 1 2 3; do
  python3 lab/gate2/calls.py --label "e5nv$n" --profiles P1,P1-blocked --call-s 180 --no-video --skip-build || code=$?
  echo "p1_step1.sh e5nv$n: done (code so far $code)"
done
python3 lab/e5/p1_step1.py e5nv1 e5nv2 e5nv3 || code=$?
echo "p1_step1.sh judged: done (code $code)"
exit "$code"
