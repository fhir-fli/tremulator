#!/bin/bash
# The Gate 2 pipeline on the laptop: no Docker, no shaping. Proves the client
# bundle, a real fhirant and the canary scan work together before any lab run.
#   bash lab/gate2/dry_run.sh <out-dir>
set -u
OUT=${1:?out dir}; mkdir -p "$OUT"
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(cd "$HERE/../.." && pwd)
FHIRANT=$(cd "$REPO/../fhirant/packages/fhirant_server" && pwd)
CLIENT="$REPO/packages/tremulator_client/build/cli/bundle/bin/tremulator_client"
PORT=$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
mkdir -p "$OUT/empty-spec" "$OUT/db" "$OUT/alice" "$OUT/bob"
# setsid: the server gets its own process group, so the stop below reaches
# the Dart VM that `dart run` spawns underneath itself (a plain kill of the
# wrapper left the VM running, 2026-10-06).
setsid bash -c "cd '$FHIRANT' && exec dart run bin/server.dart --dev-mode --port $PORT --db-path '$OUT/db' --spec-path '$OUT/empty-spec'" > "$OUT/server.log" 2>&1 &
SRV=$!
echo "server pid $SRV (process group) port $PORT"
for i in $(seq 1 120); do curl -fsS "http://127.0.0.1:$PORT/health" > /dev/null 2>&1 && break; sleep 1; done
curl -fsS "http://127.0.0.1:$PORT/health" > /dev/null || { echo "server never came up"; kill $SRV; exit 1; }
CANARY="canary-$(python3 -c 'import secrets;print(secrets.token_hex(6))')"
echo "$CANARY" > "$OUT/canary.txt"
N=${N:-10}
"$CLIENT" --server "http://127.0.0.1:$PORT" --name bob --state "$OUT/bob" --out "$OUT/bob.jsonl" --listen-s 40 > "$OUT/bob.stdout" 2>&1 &
BOB=$!
sleep 3
"$CLIENT" --server "http://127.0.0.1:$PORT" --name alice --state "$OUT/alice" --out "$OUT/alice.jsonl" --peer bob --send "$N" --interval-ms 500 --listen-s 5 --canary "$CANARY" > "$OUT/alice.stdout" 2>&1
echo "alice exit $?"
wait $BOB; echo "bob exit $?"
curl -s "http://127.0.0.1:$PORT/Communication?_count=1000&_format=json" > "$OUT/server_dump.json"
kill -INT -- -$SRV; for i in $(seq 1 20); do kill -0 -- -$SRV 2>/dev/null || break; sleep 1; done; kill -KILL -- -$SRV 2>/dev/null; wait $SRV 2>/dev/null
cp "$OUT/db/fhirant.db" "$OUT/fhirant.db"
for i in $(seq 0 $((N-1))); do printf '%s\t%s-%s\n' "$i" "$CANARY" "$i"; done > "$OUT/canaries.tsv"
python3 -I "$REPO/lab/adversary/canary_scan.py" "$OUT/canaries.tsv" "$OUT/canary_hits.jsonl" "$OUT/server_dump.json" "$OUT/fhirant.db" "$OUT/alice.jsonl" "$OUT/bob.jsonl"
echo "canary scan exit $? (0 = clean; alice/bob logs are the sender/receiver and are expected NOT to hold the canary either: the logs carry seq and times only)"
echo "sent: $(grep -c '"event":"sent"' "$OUT/alice.jsonl")  received: $(grep -c '"event":"received"' "$OUT/bob.jsonl")"
grep -h '"event":"received"' "$OUT/bob.jsonl" | python3 -c 'import sys,json; l=sorted(json.loads(x)["one-way-ms"] for x in sys.stdin); print("one-way ms: median", l[len(l)//2] if l else None, "max", l[-1] if l else None)'
