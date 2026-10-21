#!/usr/bin/env bash
# Every calls26 run's voice numbers again with today's voice_delay.py, into
# results/<label>-reanalysed.jsonl (the latest line is the one e7_table.py
# reads). Nothing runs in Docker. Self-checks first: a failing instrument
# stops it.
#
#     bash lab/gate2/calls_e7_reanalyse26.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
S=$(mktemp -d -p "$HERE/build")
python3 voice_delay.py --self-check "$S/plain" > /dev/null
python3 voice_delay.py --self-check-speech "$S/speech" > /dev/null
rm -rf "$S"
echo "self-checks pass $(date +%T)"
for n in 1 2 3; do
  for arm in fc fd dc dd; do
    python3 calls.py --label "calls26$n$arm" --reanalyse > /dev/null
    echo "calls26$n$arm done $(date +%T)"
  done
done
