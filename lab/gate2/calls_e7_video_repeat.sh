#!/usr/bin/env bash
# E7 step 4, with video (docs/GATE2-CALLS-PLAN.md; plan Grey approved
# 2026-10-18; Grey "go" 2026-10-21 on the video calls). Whether leaving
# abs-send-time and transport-cc out of the audio section (RFC 8285) helps
# or harms a call that also sends video. calls26 (sound only): no relay
# queue with them left out (0/3 against 2/3), lower median voice delay in
# 9/9 pairs, clicks heard alike (241 control vs 243 of 261, measured with 385c91e).
# Three rounds, each the control then the drop, so drift falls on both:
#   <L><n><P>fc / fd  <P> direct and relayed, relay on the field link
#   <L><n><P>dc / dd  <P> relayed, relay on a decent link
# for P in P1 P2 P3. Video from Alice, speech, Opus 12 kbit/s, 60 ms, DTX,
# 300 s calls; each phone's packets captured (calls.media_capture). The app
# is calls23's build (unchanged since).
# Stops at the first run that fails. Needs Grey's go (docs/GATE1.md).
#
#     bash lab/gate2/calls_e7_video_repeat.sh calls28
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
L=$1
run() {
  local label=$1 profiles=$2; shift 2
  python3 "$HERE/calls.py" --label "$label" --call-s 300 --profiles "$profiles" \
    --speech --opus-max-bitrate 12000 --opus-ptime 60 --opus-dtx \
    --skip-build "$@" > "$HERE/results/$label.out" 2>&1
  echo "$label exit 0" >> "$HERE/results/$label.out"
}
DROP=(--audio-drop abs-send-time,transport-cc)
for n in 1 2 3; do
  for p in P1 P2 P3; do
    run "${L}${n}${p}fc" "$p,$p-blocked" --relay-link field
    run "${L}${n}${p}fd" "$p,$p-blocked" --relay-link field "${DROP[@]}"
    run "${L}${n}${p}dc" "$p-blocked" --relay-link decent
    run "${L}${n}${p}dd" "$p-blocked" --relay-link decent "${DROP[@]}"
  done
done
