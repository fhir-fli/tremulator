#!/bin/bash
# Starts the phone's virtual screen and sound card, then waits. calls.py runs
# the app and the media tools in it with docker exec.
set -u
mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"
Xvfb :0 -screen 0 1280x720x24 -nolisten tcp > /tmp/xvfb.log 2>&1 &
for _ in $(seq 1 40); do xdpyinfo > /dev/null 2>&1 && break; sleep 0.25; done
pulseaudio --start --exit-idle-time=-1 > /tmp/pulse.log 2>&1
for _ in $(seq 1 40); do pactl info > /dev/null 2>&1 && break; sleep 0.25; done
pactl load-module module-null-sink sink_name=mic > /dev/null
pactl load-module module-null-sink sink_name=speaker > /dev/null
pactl set-default-source mic.monitor
pactl set-default-sink speaker
if xdpyinfo > /dev/null 2>&1 && pactl info > /dev/null 2>&1; then
  touch /tmp/phone-ready
else
  echo "screen or sound did not start" > /tmp/phone-failed
fi
exec sleep infinity
