#!/usr/bin/env bash
# Proves lip_drift.py before any call is measured with it: in one lab phone
# (no call, no network) a single player shows the flashing box and plays a
# 30 ms 1500 Hz beep at each flash's onset; the beep is delayed by SHIFT_MS.
# The phone grabs the box and records its own sound exactly as a call does.
# Pass: the median offset reads SHIFT_MS within one frame (33 ms), for
# SHIFT_MS 0 and 500.
#
#     bash lab/gate2/calls_lip_drift_check.sh 0     (then 500)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
SHIFT=$1
OUT="$HERE/results/lipcheck$SHIFT"
C=g2c-lipcheck
rm -rf "$OUT"; mkdir -p "$OUT"; chmod 777 "$OUT"
docker rm -f $C > /dev/null 2>&1 || true
docker run -d --rm --name $C --network none -v "$OUT:/out" tremulator-g2-calls:latest > /dev/null
for _ in $(seq 1 60); do docker exec $C test -e /tmp/phone-ready && break; sleep 0.5; done
docker exec $C test -e /tmp/phone-ready
VIDEO=$(python3 -c "import sys; sys.path.insert(0, '$HERE'); import lip_drift; print(lip_drift.picture_filter())")
SOUND="sine=frequency=1500:sample_rate=48000,volume=volume=0:enable='gte(mod(t\\,10)\\,0.03)',adelay=$SHIFT:all=1"
GRAB=$(python3 -c "import sys; sys.path.insert(0, '$HERE'); import lip_drift; print(lip_drift.grab_cmd('/out/check', 90))")
REC=$(python3 -c "import sys; sys.path.insert(0, '$HERE'); import voice_delay; print(voice_delay.record_cmd('speaker.monitor', '/out/check_sound', 90))")
docker exec -d $C sh -c "$GRAB"
docker exec -d $C sh -c "$REC"
sleep 2
docker exec -d $C sh -c "ffplay -loglevel error -noborder -left 0 -top 0 -x 1280 -y 720 -f lavfi \"$VIDEO[out0];$SOUND[out1]\" > /out/ffplay.log 2>&1"
sleep 65
docker exec $C sh -c "pkill -x ffplay; pkill -INT -x ffmpeg; true"
sleep 3
docker rm -f $C > /dev/null
python3 "$HERE/lip_drift.py" --check "$OUT" "$SHIFT"
