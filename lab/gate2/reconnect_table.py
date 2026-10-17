#!/usr/bin/env python3
"""One row per call of a calls run, for the reconnection (E8) question: how
each phone's call ended, whether and how fast it reconnected, the restarts,
the clicks heard before and after a link cut, frozen video, fingerprints.

    python3 lab/gate2/reconnect_table.py results/calls10.jsonl
"""
import json
import sys

for line in open(sys.argv[1]):
    r = json.loads(line)
    if "profile" not in r:
        continue
    row = {"profile": r["profile"], "exits": [r.get("alice_exit"), r.get("bob_exit")]}
    for who in ("alice", "bob"):
        a = r.get(who) or {}
        row[who] = {"route": a.get("route"), "connect_ms": a.get("connect-ms"), "ended": a.get("ended"),
                    "lost": len(a.get("reconnecting") or []), "back_ms": a.get("reconnected-ms"),
                    "control": a.get("reconnected-control"), "restarts": a.get("restarts-sent"),
                    "restarts_failed": a.get("restarts-failed"), "applied": a.get("answers-applied"),
                    "answered": a.get("answers-sent"), "hangup_not_sent": a.get("hangup-not-sent")}
    v = r.get("voice") or {}
    row["voice"] = [v.get("clicks_heard"), v.get("clicks_sent"), v.get("delay_median_ms")]
    row["cut"] = {k: x for k, x in (r.get("cut") or {}).items() if not k.endswith(("_start", "_end"))}
    rb = r.get("recording_bob") or {}
    row["bob_frozen_s_per_min"] = rb.get("frozen_s_per_min")
    row["fingerprints"] = [r.get("fingerprint_hits"), r.get("fingerprint_control_hits")]
    print(json.dumps(row), flush=True)
