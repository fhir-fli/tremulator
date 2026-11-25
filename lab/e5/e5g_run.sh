#!/usr/bin/env bash
# E5g (docs/GATE2-CALLS-PLAN.md): libwebrtc's loss-based padding off, with
# --webrtc-field-trial WebRTC-Bwe-LossBasedBweV2/PaddingDuration:0ms/
# against E5f, the only change (lab/e5/PADDING.md). Gate 1's arrangement
# (only Alice's link shaped), three passes of P1-P4 direct and relay-forced,
# 3-minute calls; the first pass builds the app (the vendored plugin with
# the fieldTrials option is new), the rest --skip-build. Then the table and
# the idle video packet counts.
#
#     bash lab/e5/e5g_run.sh
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE/../.."
grep -q 'fieldTrials' third_party/flutter_webrtc/common/cpp/src/flutter_webrtc.cc || { echo "e5g_run.sh: this tree lacks the fieldTrials option"; exit 1; }
T='WebRTC-Bwe-LossBasedBweV2/PaddingDuration:0ms/'
P=P1,P2,P3,P4,P1-blocked,P2-blocked,P3-blocked,P4-blocked
code=0
build=
for n in 1 2 3; do
  python3 lab/gate2/calls.py --label "e5g$n" --profiles "$P" --call-s 180 --shape-only alice --opus-ptime 60 --no-suspend-video --video-min-kbps 10 --webrtc-field-trial "$T" $build || code=$?
  echo "e5g_run.sh e5g$n: done (code so far $code)"
  build=--skip-build
done
python3 lab/e5/table.py --name=e5g e5g1 e5g2 e5g3 || code=$?
(cd lab/gate2/results && for r in e5g1 e5g2 e5g3; do python3 ../../e5/idle_video_packets.py $r; done) > lab/e5/results/e5g_idle_video_packets.txt || code=$?
echo "e5g_run.sh table: done (code $code)"
exit "$code"
