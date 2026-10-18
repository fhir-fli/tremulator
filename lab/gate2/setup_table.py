#!/usr/bin/env python3
"""The setup-during-outage table (calls12-14): one row per run and profile,
from each profile's summary line and both phones' raw logs.

    python3 -I lab/gate2/setup_table.py calls12 calls13 calls14

Columns: whether Alice connected; seconds from placing the call to
connected; seconds from the link coming back (the later phone's cut end, for
the setup cuts) to connected; how each phone's call ended; sends of an offer
or answer that failed and were repeated; never-connected failures and what
the transport said (route or handshake); collects that failed; clicks heard;
Bob's frozen seconds per minute; fingerprint hits in the server's data.
"""
import json
import os
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))


def events(path):
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path):
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    return out


def stamp(e):
    return datetime.fromisoformat(e["t"].replace("Z", "+00:00")).timestamp()


def first(evs, name):
    return next((e for e in evs if e.get("event") == name), None)


def row(label, rec):
    d = os.path.join(HERE, "results", label, rec["profile"])
    a = events(os.path.join(d, "alice.jsonl"))
    b = events(os.path.join(d, "bob.jsonl"))
    started, connected = first(a, "call-started"), first(a, "connected")
    cut = rec.get("cut") or {}
    ends = [cut.get(k) for k in ("alice_end", "bob_end") if cut.get(k)]
    back = None
    if connected and ends:
        back = round(stamp(connected) - max(ends), 1)
    ended = {w: next((e["why"] for e in evs if e.get("event") == "call-ended"), None)
             for w, evs in (("alice", a), ("bob", b))}
    voice = rec.get("voice") or {}
    return {
        "run": label,
        "profile": rec["profile"],
        "connected": connected is not None,
        "route": rec.get("alice", {}).get("route"),
        "placed_to_connected_s": round(stamp(connected) - stamp(started), 1)
        if connected and started else None,
        "link_back_to_connected_s": back,
        "ended_alice": ended["alice"],
        "ended_bob": ended["bob"],
        "send_failed": {w: sum(e.get("event") == "send-failed" for e in evs)
                        for w, evs in (("alice", a), ("bob", b))},
        "setup_failed": [(w, e.get("why"), e.get("dtls")) for w, evs in (("alice", a), ("bob", b))
                         for e in evs if e.get("event") == "setup-failed"],
        "collect_failed": {w: sum(e.get("event") == "collect-failed" for e in evs)
                           for w, evs in (("alice", a), ("bob", b))},
        "clicks": f"{voice.get('clicks_heard')}/{voice.get('clicks_sent')}",
        "bob_frozen_s_per_min": (rec.get("recording_bob") or {}).get("frozen_s_per_min"),
        "fingerprint_hits": rec.get("fingerprint_hits"),
        "exits": (rec.get("alice_exit"), rec.get("bob_exit")),
    }


def main():
    for label in sys.argv[1:]:
        for rec in events(os.path.join(HERE, "results", f"{label}.jsonl")):
            if "profile" in rec:
                print(json.dumps(row(label, rec)), flush=True)


if __name__ == "__main__":
    main()
