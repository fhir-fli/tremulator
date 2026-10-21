"""Run from lab/gate2. One line per finished call of a calls28 label: the
voice numbers, when the guard started and stopped video, and whether Bob's
sound playout aimed above what the network needed once video had stopped.
calls281P1fd: after a video burst Bob's playout target held at 1,025 ms
(P1) and 950 ms (P1-blocked) to the end of the call while its
network-driven minimum fell to 40-100 ms; in both controls the two stayed
equal and fell back to 100-300 ms.

usage: python3 e7_video_calls.py OUT.jsonl LABEL..."""
import json
import os
import statistics
import sys

OUT = sys.argv[1]


def stats(path):
    for line in open(path):
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("event") == "stats":
            yield e


def playout(path):
    """(target ms, minimum ms) of Bob's sound per stats interval."""
    pts = []
    for e in stats(path):
        for x in e["reports"]:
            if x["type"] == "inbound-rtp" and x.get("kind") == "audio":
                pts.append((x["jitterBufferTargetDelay"], x["jitterBufferMinimumDelay"],
                            x["jitterBufferEmittedCount"]))
    return [(1000 * (b[0] - a[0]) / (b[2] - a[2]), 1000 * (b[1] - a[1]) / (b[2] - a[2]))
            for a, b in zip(pts, pts[1:]) if b[2] > a[2]]


with open(OUT, "a") as out:
    for label in sys.argv[2:]:
        p = os.path.join("results", f"{label}.jsonl")
        if not os.path.exists(p):
            continue
        for line in open(p):
            r = json.loads(line)
            if "profile" not in r:
                continue
            d = os.path.join("results", label, r["profile"])
            video = []
            for line2 in open(os.path.join(d, "alice.jsonl")):
                try:
                    e = json.loads(line2)
                except json.JSONDecodeError:
                    continue
                if e.get("event") == "video-sending":
                    video.append([e["t"][11:19], e["sending"], e["by"], e["rtt"]])
            pl = playout(os.path.join(d, "bob.jsonl"))
            last = pl[-60:]  # the last ~2 minutes
            delays = [x["delay_ms"] for x in map(json.loads, open(os.path.join(d, "voice_delay.jsonl")))]
            heard = [x for x in delays if x is not None]
            out.write(json.dumps({
                "run": label, "profile": r["profile"], "opus": r.get("opus"),
                "relay_link": r.get("relay_link"), "exits": [r.get("alice_exit"), r.get("bob_exit")],
                "clicks": f"{len(heard)}/{len(delays)}",
                "delay_median_ms": round(statistics.median(heard)) if heard else None,
                "delay_last5_ms": round(statistics.median(heard[-5:])) if heard else None,
                "video": video,
                "end_target_ms": round(statistics.median(t for t, _ in last)) if last else None,
                "end_minimum_ms": round(statistics.median(m for _, m in last)) if last else None,
            }) + "\n")
            out.flush()
