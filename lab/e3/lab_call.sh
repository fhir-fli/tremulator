#!/usr/bin/env bash
# E3: one lab run (lab/gate2/calls.py) from the
# current directory's copy of the code, then its results copied into this
# repository's lab/e3/results/LABEL (the copy from plant.sh is removed
# afterwards, and its results with it). The canary scan's counts are in
# LABEL.jsonl: fingerprint_hits (on the server) and fingerprint_control_hits
# (the phones' own logs, the positive control).
#
#     bash lab/e3/plant.sh NAME bash lab/e3/lab_call.sh LABEL [calls.py options]
#
# With no options: --profiles none --call-s 30.
set -uo pipefail
label=$1; shift
[ $# -gt 0 ] || set -- --profiles none --call-s 30
HERE=$(cd "$(dirname "$0")" && pwd)
MAIN=$(git -C "$HERE" worktree list --porcelain | awk 'NR==1{print $2}')
OUT="$MAIN/lab/e3/results"
code=0
python3 lab/gate2/calls.py --label "$label" "$@" || code=$?
mkdir -p "$OUT/$label"
cp -r lab/gate2/results/"$label"/. "$OUT/$label/" 2> /dev/null
cp lab/gate2/results/"$label".jsonl "$OUT/" 2> /dev/null
echo "lab_call.sh $label: calls.py exit $code; results in $OUT/$label"
exit "$code"
