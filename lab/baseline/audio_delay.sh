#!/usr/bin/env bash
# Record the laptop microphone for the one-way audio delay test. Both phones
# in the room, receiving phone on loudspeaker. One sharp click near the sending
# phone; the microphone hears the click directly and then again from the
# receiving phone's speaker. The gap is the one-way delay (plus the speaker
# path, under 10 ms). Find the onsets with
# `dart run lab/tool/bin/baseline_onsets.dart results/<label>.wav`.
#
#   audio_delay.sh <label> [seconds=20]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
label="${1:?label}"; secs="${2:-20}"
case "$label" in -*) echo "label must not start with -" >&2; exit 2;; esac
out="$here/results/$label.wav"
[ -e "$out" ] && { echo "$out exists" >&2; exit 2; }
echo "recording $secs s from the default microphone -> $out"
ffmpeg -hide_banner -loglevel error -f pulse -i default -ac 1 -ar 16000 -sample_fmt s16 -t "$secs" "$out"
printf '%s %s %s s\n' "$(date -Is)" "$label" "$secs" >>"$here/results/audio.log"
echo "done"
