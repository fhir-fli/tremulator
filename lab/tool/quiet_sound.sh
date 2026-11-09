#!/usr/bin/env bash
# Runs a command (the call integration tests) with its sound on two silent
# dummy devices, never the desktop's speakers or microphone. The tests open
# the default microphone and play the far phone's sound; run bare, they
# played through Grey's speakers (2026-11-09). libwebrtc opens the default
# device by passing no name (audio_device_pulse_linux.cc, device index 0),
# so libpulse takes PULSE_SINK / PULSE_SOURCE. Every 0.3 s the streams are
# listed into LOG; a stream from the test on any other device kills the
# command. The dummies are removed afterwards.
#
#     bash lab/tool/quiet_sound.sh LOG -- flutter test integration_test/calls_test.dart -d linux
set -uo pipefail
LOG=$1; shift 2
rm -f "$LOG.killed"
OUT_MOD=$(pactl load-module module-null-sink sink_name=tremulator_test_out sink_properties=device.description=tremulator_test_out)
MIC_MOD=$(pactl load-module module-null-sink sink_name=tremulator_test_mic sink_properties=device.description=tremulator_test_mic)
trap 'pactl unload-module "$OUT_MOD"; pactl unload-module "$MIC_MOD"' EXIT
OUT=$(pactl list short sinks | awk '$2=="tremulator_test_out"{print $1}')
MIC=$(pactl list short sources | awk '$2=="tremulator_test_mic.monitor"{print $1}')
PULSE_SINK=tremulator_test_out PULSE_SOURCE=tremulator_test_mic.monitor setsid "$@" &
PID=$!
echo "pid $PID out=$OUT mic=$MIC" >> "$LOG"
check() {  # $1 sink-inputs|source-outputs, $2 key, $3 allowed device id
  pactl list "$1" | awk -v k="$2" '/^(Sink Input|Source Output)/{id=$3} $1==k{s=$2} /application.process.binary/{print id, s, $3}' |
    while read -r id s bin; do
      echo "$(date +%T) $1 $id $s $bin" >> "$LOG"
      # 4294967295 is PA_INVALID_INDEX: a stream not yet attached to any
      # device, so playing nowhere (seen 2026-11-09 for one poll at setup).
      if [ "$s" != "$3" ] && [ "$s" != 4294967295 ] && grep -qi 'example\|flutter\|tremulator' <<< "$bin"; then
        echo "$(date +%T) WRONG DEVICE, killing" >> "$LOG"; touch "$LOG.killed"; kill -- -"$PID"
      fi
    done
}
while kill -0 "$PID" 2>/dev/null; do
  check sink-inputs Sink: "$OUT"
  check source-outputs Source: "$MIC"
  sleep 0.3
done
wait "$PID"; RC=$?
# A killed run can still exit 0 (2026-11-09: flutter test did), so the
# kill itself sets the code.
if [ -e "$LOG.killed" ]; then rm -f "$LOG.killed"; RC=99; fi
echo "exit $RC" >> "$LOG"
exit "$RC"
