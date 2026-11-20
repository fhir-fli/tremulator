#!/usr/bin/env bash
# E1: a browser calls the app. The app's web build in Chrome for Testing
# 158.0.8127.36 (calls.py --browser) against the Linux app, each way, on an
# unshaped link, on P2 direct and on P2 relayed (P2-blocked); the same calls
# Linux to Linux as the reference; and the planted wrong certificate read by
# Chrome, each way. Shipped settings (no Opus or header options), 120 s
# calls, 30 s for the planted ones. The first run builds everything.
# Method and pass rule, fixed before the run (2026-11-19): e1_check.py.
#
#     bash lab/gate2/calls_e1.sh calls47
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
BUILD=(--keep-server)
LABELS=()
run() {
  local label=$1 call_s=$2; shift 2
  python3 "$HERE/calls.py" --label "$label" --call-s "$call_s" "${BUILD[@]}" "$@" \
    > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
  BUILD=(--skip-build --keep-server)
  LABELS+=("$label")
}
# The first build makes both images: the browser image needs --browser.
run "${L}bb" 120 --profiles none,P2,P2-blocked --browser bob
run "${L}ba" 120 --profiles none,P2,P2-blocked --browser alice
run "${L}nat" 120 --profiles none,P2,P2-blocked
run "${L}pb" 30 --profiles none --browser bob --plant-changed-fingerprint bob
run "${L}pa" 30 --profiles none --browser alice --plant-changed-fingerprint alice
cd "$HERE" && python3 e1_check.py "results/${L}-e1.jsonl" "${LABELS[@]}"
