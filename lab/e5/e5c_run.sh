#!/usr/bin/env bash
# E5c (docs/GATE2-CALLS-PLAN.md): the video fix against E5b's A (only
# Alice's link shaped, Gate 1's arrangement), one variable at a time:
#   B  flutter_webrtc 1.6.3, video still stopped with replaceTrack(null)
#      (commit e092bcd, built from a worktree), against E5b A: the library;
#   F  1.6.3 with video stopped by the encoding's active flag (this tree),
#      against B: the fix.
# Three passes each of P1-P4 direct and relay-forced, 3-minute calls; then
# the two tables.
#
#     bash lab/e5/e5c_run.sh WORKTREE_DIR
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
MAIN=$(cd "$HERE/../.." && pwd)
WT=$1
BASE=e092bcd
P=P1,P2,P3,P4,P1-blocked,P2-blocked,P3-blocked,P4-blocked
code=0
cd "$MAIN"
git worktree add --detach "$WT" "$BASE" || exit 1
# The same resolved packages as this tree (lock files are not committed).
for f in app/pubspec.lock lab/tool/pubspec.lock packages/*/pubspec.lock packages/tremulator_calls/example/pubspec.lock; do
  cp "$MAIN/$f" "$WT/$f" || exit 1
done
# Each tree is the code it claims to be.
grep -q 'replaceTrack(sending ? track : null)' "$WT/packages/tremulator_calls/lib/src/calls.dart" || { echo "e5c_run.sh: base is not the replaceTrack code"; exit 1; }
grep -q '_setVideoActive' "$MAIN/packages/tremulator_calls/lib/src/calls.dart" || { echo "e5c_run.sh: this tree lacks the fix"; exit 1; }
grep -q 'flutter_webrtc: 1.6.3' "$WT/app/pubspec.yaml" || { echo "e5c_run.sh: base is not on 1.6.3"; exit 1; }
(cd "$WT/lab/tool" && dart pub get > /dev/null) || exit 1
for n in 1 2 3; do
  build=--skip-build; [ "$n" = 1 ] && build=--keep-server
  (cd "$WT" && python3 lab/gate2/calls.py --label "e5cB$n" --profiles "$P" --call-s 180 --shape-only alice $build) || code=$?
  mv "$WT/lab/gate2/results/e5cB$n" "$WT/lab/gate2/results/e5cB$n.jsonl" "$MAIN/lab/gate2/results/" || code=$?
  echo "e5c_run.sh e5cB$n: done (code so far $code)"
done
for n in 1 2 3; do
  build=--skip-build; [ "$n" = 1 ] && build=--keep-server
  python3 lab/gate2/calls.py --label "e5cF$n" --profiles "$P" --call-s 180 --shape-only alice $build || code=$?
  echo "e5c_run.sh e5cF$n: done (code so far $code)"
done
python3 lab/e5/table.py --name=e5c_B e5cB1 e5cB2 e5cB3 || code=$?
python3 lab/e5/table.py --name=e5c_F e5cF1 e5cF2 e5cF3 || code=$?
git worktree remove --force "$WT" || code=$?
echo "e5c_run.sh tables: done (code $code)"
exit "$code"
