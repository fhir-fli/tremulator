"""Run from lab/gate2. How long the phones take to agree that video is off or
on again (E7 calls31, Calls.closeStoppedVideo). One line per call; one entry
per video start or stop on Alice, timed from her video-sending event:
bob_saw_s, Bob's remote-video from the control channel (both arms); and with
the fix, the new offer by its number n (video-offer-sent): offer_sent_s and
bob_answer_s when each phone's upload returned (Calls._deliver reports after
sendCall returns, which can be after the server has passed it on: calls311c1
P1 n=1, Bob answered 3.6 s before Alice's upload returned), applied_s when
Alice applied Bob's answer (the phones agree from then), or ignored when a
later offer had replaced it. calls311c1 P1 stop (n=2): applied 32.9 s.

usage: python3 e7_close_timing.py OUT.jsonl LABEL..."""
import json
import os
import sys
from datetime import datetime


def events(path):
    for line in open(path):
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "event" in e and "t" in e:
            e["at"] = datetime.fromisoformat(e["t"].replace("Z", "+00:00"))
            yield e


def after(evs, t0, name, **match):
    """Seconds from t0 to the first `name` event at or after t0 matching."""
    for e in evs:
        if e["event"] == name and e["at"] >= t0 and all(e.get(k) == v for k, v in match.items()):
            return round((e["at"] - t0).total_seconds(), 2)
    return None


with open(sys.argv[1], "a") as out:
    for label in sys.argv[2:]:
        for line in open(os.path.join("results", f"{label}.jsonl")):
            r = json.loads(line)
            if "profile" not in r:
                continue
            d = os.path.join("results", label, r["profile"])
            alice = list(events(os.path.join(d, "alice.jsonl")))
            bob = list(events(os.path.join(d, "bob.jsonl")))
            changes = []
            for e in alice:
                if e["event"] != "video-sending":
                    continue
                t0 = e["at"]
                # _sendVideo reports video-offer-sent, then video-sending
                offer = next((o for o in reversed(alice) if o["event"] == "video-offer-sent"
                              and 0 <= (t0 - o["at"]).total_seconds() < 1), None)
                c = {"t": e["t"][11:19], "sending": e["sending"], "by": e["by"],
                     "bob_saw_s": after(bob, t0, "remote-video", sending=e["sending"])}
                if offer:
                    n = offer["n"]
                    c.update({"n": n,
                              "offer_sent_s": after(alice, offer["at"], "offer-sent", n=n),
                              "bob_answer_s": after(bob, offer["at"], "answer-sent", n=n),
                              "applied_s": after(alice, offer["at"], "answer-applied", n=n),
                              "ignored": after(alice, offer["at"], "answer-ignored", n=n) is not None})
                changes.append(c)
            out.write(json.dumps({
                "run": label, "profile": r["profile"],
                "close": (r.get("opus") or {}).get("close-stopped-video"),
                "exits": [r.get("alice_exit"), r.get("bob_exit")],
                "changes": changes,
                "bob_reconnects": [e.get("ms") for e in bob if e["event"] == "reconnected"],
                "bob_reconnecting": sum(e["event"] == "reconnecting" for e in bob),
            }) + "\n")
            out.flush()
