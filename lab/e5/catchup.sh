#!/usr/bin/env bash
# E5 catch-up: the calls the first two passes lost to the onset-detector
# hang (e5r1 stopped after P1 at P2's voice; e5r2 at P3-blocked's voice),
# run once run.sh has finished, then the table over all passes.
#
#     bash lab/e5/catchup.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
until grep -q "run.sh table: done" lab/e5/results/run.out; do sleep 20; done
code=0
python3 lab/gate2/calls.py --label e5r1b --profiles P2,P3,P4,P5,P0,P1-blocked,P2-blocked,P3-blocked --call-s 180 --skip-build || code=$?
echo "catchup.sh e5r1b: done (code so far $code)"
python3 lab/gate2/calls.py --label e5r2b --profiles P3-blocked --call-s 180 --skip-build || code=$?
echo "catchup.sh e5r2b: done (code so far $code)"
python3 lab/e5/table.py e5r1 e5r1b e5r2 e5r2b e5r3 || code=$?
echo "catchup.sh table: done (code $code)"
exit "$code"
