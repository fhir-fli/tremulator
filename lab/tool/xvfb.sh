#!/bin/bash
# A private virtual screen for tests that need one (the Flutter Linux build
# of tremulator_calls). Never the live desktop. No root needed: the Ubuntu
# xvfb package is unpacked, not installed, under lab/tool/.xvfb (gitignored).
#   bash lab/tool/xvfb.sh [display]     # default :99; prints the pid
set -eu
D=${1:-:99}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT="$HERE/.xvfb"
BIN="$ROOT/root/usr/bin/Xvfb"
if [ ! -x "$BIN" ]; then
  mkdir -p "$ROOT"
  (cd "$ROOT" && apt-get download xvfb && dpkg -x xvfb_*.deb root)
fi
if DISPLAY=$D xdpyinfo > /dev/null 2>&1; then
  echo "display $D already answers"; exit 0
fi
"$BIN" "$D" -screen 0 1280x720x24 -nolisten tcp > "$ROOT/xvfb${D#:}.log" 2>&1 &
PID=$!
for _ in $(seq 1 20); do DISPLAY=$D xdpyinfo > /dev/null 2>&1 && break; sleep 0.5; done
DISPLAY=$D xdpyinfo > /dev/null 2>&1 || { echo "Xvfb on $D never answered; see $ROOT/xvfb${D#:}.log"; exit 1; }
echo "Xvfb $D pid $PID"
