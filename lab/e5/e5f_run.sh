#!/usr/bin/env bash
# E5f (docs/GATE2-CALLS-PLAN.md): the video's lowest rate at 10 kbit/s,
# with --video-min-kbps 10 against E5e, the only change (video's lowest
# rate under the free room P1 leaves; lab/e5/RESULTS-E5e.md). Gate 1's arrangement (only Alice's link
# shaped), three passes of P1-P4 direct and relay-forced, 3-minute calls;
# the first pass builds the app (Calls.videoMinBitrate is new), the rest --skip-build. Then the table.
#
#     bash lab/e5/e5f_run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
grep -q 'videoMinBitrate' packages/tremulator_calls/lib/src/calls.dart || { echo "e5f_run.sh: this tree lacks Calls.videoMinBitrate"; exit 1; }
P=P1,P2,P3,P4,P1-blocked,P2-blocked,P3-blocked,P4-blocked
code=0
build=
for n in 1 2 3; do
  python3 lab/gate2/calls.py --label "e5f$n" --profiles "$P" --call-s 180 --shape-only alice --opus-ptime 60 --no-suspend-video --video-min-kbps 10 $build || code=$?
  echo "e5f_run.sh e5f$n: done (code so far $code)"
  build=--skip-build
done
python3 lab/e5/table.py --name=e5f e5f1 e5f2 e5f3 || code=$?
echo "e5f_run.sh table: done (code $code)"
exit "$code"
