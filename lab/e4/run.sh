#!/usr/bin/env bash
# E4: two 60 s calls forced through the relay (none-blocked), the relay
# recording every packet (calls.py --relay-capture), each then scanned
# (relay_scan.py). Results: lab/gate2/results/LABEL/ (calls.py's own) and
# lab/e4/results/LABEL.jsonl (the scan).
#
#     bash lab/e4/run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
mkdir -p lab/e4/results
code=0
for label in e4a e4b; do
  skip=""; [ "$label" = e4b ] && skip="--skip-build"
  python3 lab/gate2/calls.py --label "$label" --profiles none-blocked --call-s 60 --relay-capture $skip || code=$?
  python3 lab/e4/relay_scan.py "lab/gate2/results/$label/none-blocked" "lab/e4/results/$label.jsonl" || code=$?
  echo "run.sh $label: done (code so far $code)"
done
exit "$code"
