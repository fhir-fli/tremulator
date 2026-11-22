#!/usr/bin/env bash
# E5b (docs/GATE2-CALLS-PLAN.md): A, only Alice's link shaped (Gate 1's
# arrangement), and C, only Bob's (a ground server behind a weak uplink),
# three passes each of P1-P4 direct and relay-forced, 3-minute calls,
# shipped defaults; then the two tables.
#
#     bash lab/e5/e5b_run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
P=P1,P2,P3,P4,P1-blocked,P2-blocked,P3-blocked,P4-blocked
code=0
for arr in A C; do
  who=alice; [ "$arr" = C ] && who=bob
  for n in 1 2 3; do
    python3 lab/gate2/calls.py --label "e5b$arr$n" --profiles "$P" --call-s 180 --shape-only "$who" --skip-build || code=$?
    echo "e5b_run.sh e5b$arr$n: done (code so far $code)"
  done
done
python3 lab/e5/table.py --name=e5b_A e5bA1 e5bA2 e5bA3 || code=$?
python3 lab/e5/table.py --name=e5b_C --no-whatsapp e5bC1 e5bC2 e5bC3 || code=$?
echo "e5b_run.sh tables: done (code $code)"
exit "$code"
