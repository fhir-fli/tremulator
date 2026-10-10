#!/bin/bash
# The calls pipeline on the laptop: no Docker, no shaping, no sound (the
# laptop's microphone is never opened). One fhirant by `dart run`, two copies
# of the app's Linux build, each on its own private Xvfb (Alice :99, Bob :98).
# A test pattern plays full screen on Alice's; she calls Bob with her screen
# as the picture; Bob's screen is recorded. Proves the app places, answers,
# shows and measures a call before any lab run.
#   bash lab/gate2/calls_dry_run.sh <out-dir> [call-seconds]
set -u
OUT=${1:?out dir}; CALL_S=${2:-15}; mkdir -p "$OUT"
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
FHIRANT=$(cd "$REPO/../fhirant/packages/fhirant_server" && pwd)
APP="$REPO/app/build/linux/x64/release/bundle/tremulator"
[ -x "$APP" ] || { echo "build the app first: cd app && flutter build linux --release"; exit 1; }
bash "$REPO/lab/tool/xvfb.sh" :99 || exit 1
bash "$REPO/lab/tool/xvfb.sh" :98 || exit 1
export WAYLAND_DISPLAY=
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
mkdir -p "$OUT/empty-spec" "$OUT/db" "$OUT/alice" "$OUT/bob"
# setsid: the server gets its own process group, so the stop reaches the VM
# that `dart run` spawns underneath itself.
setsid bash -c "cd '$FHIRANT' && exec dart run bin/server.dart --dev-mode --port $PORT --db-path '$OUT/db' --spec-path '$OUT/empty-spec'" > "$OUT/server.log" 2>&1 &
SRV=$!
echo "server pid $SRV (process group) port $PORT"
for i in $(seq 1 120); do curl -fsS "http://127.0.0.1:$PORT/health" > /dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://127.0.0.1:$PORT/health" > /dev/null || { echo "server never came up"; kill -- -$SRV; exit 1; }
STOP="$OUT/stop"; rm -f "$STOP"
DISPLAY=:98 "$APP" --lab --server "http://127.0.0.1:$PORT" --name bob --state "$OUT/bob" --out "$OUT/bob.jsonl" --until-file "$STOP" > "$OUT/bob.stdout" 2>&1 &
BOB=$!
echo "bob pid $BOB"
for i in $(seq 1 60); do grep -q '"waiting-for-call"' "$OUT/bob.jsonl" 2>/dev/null && break; sleep 1; done
DISPLAY=:98 ffmpeg -y -loglevel error -f x11grab -framerate 30 -video_size 1280x720 -i :98 -t $((CALL_S + 30)) -c:v libx264 -preset ultrafast -crf 30 -pix_fmt yuv420p "$OUT/bob_screen.mp4" > "$OUT/bob_record.log" 2>&1 &
REC=$!
DISPLAY=:99 "$APP" --lab --server "http://127.0.0.1:$PORT" --name alice --state "$OUT/alice" --out "$OUT/alice.jsonl" --peer bob --video --call-s "$CALL_S" > "$OUT/alice.stdout" 2>&1 &
ALICE=$!
# The pattern goes up after Alice's window, so it is on top of it (no window
# manager: the newest window is uppermost).
sleep 3
DISPLAY=:99 ffplay -loglevel error -noborder -left 0 -top 0 -x 1280 -y 720 -an -f lavfi 'testsrc2=size=1280x720:rate=30' > "$OUT/ffplay.log" 2>&1 &
PLAY=$!
wait $ALICE; echo "alice exit $?"
kill $PLAY 2>/dev/null; wait $PLAY 2>/dev/null
touch "$STOP"
for i in $(seq 1 30); do kill -0 $BOB 2>/dev/null || break; sleep 1; done
kill $BOB 2>/dev/null; wait $BOB; echo "bob exit $?"
kill -INT $REC 2>/dev/null; wait $REC 2>/dev/null
kill -INT -- -$SRV; for i in $(seq 1 20); do kill -0 -- -$SRV 2>/dev/null || break; sleep 1; done; kill -KILL -- -$SRV 2>/dev/null; wait $SRV 2>/dev/null
python3 -I "$HERE/calls_summary.py" "$OUT/alice.jsonl" "$OUT/bob.jsonl"
