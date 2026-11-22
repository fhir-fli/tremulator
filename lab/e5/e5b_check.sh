#!/usr/bin/env bash
# E5b instrument check (docs/GATE2-CALLS-PLAN.md): --shape-only alice under a
# known condition. `none` and `plus500` (500 ms each way, here on Alice's
# link only), one 60 s call each; e5b_check.py says whether the voice reads
# about 500 ms more, Alice's round trip about 1 s, and Bob's link unshaped.
#
#     bash lab/e5/e5b_check.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
python3 lab/gate2/calls.py --label e5bchk --profiles none,plus500 --shape-only alice --call-s 60 --skip-build
c=$?
python3 lab/e5/e5b_check.py e5bchk || c=$?
exit $c
