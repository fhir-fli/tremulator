"""Run from lab/gate2. For calls where the lab taps "try video again"
(--tap-video-after), video is off in stretches between a stop and the next
tap, not to the end of the call, so e7_video_calls.py's last-two-minutes
playout no longer measures "after video stopped". Method, fixed before
calls32 was read (2026-11-02):

- Off stretch: Alice's video-sending false to her next video-sending true,
  or to the call's last stats line. Only stretches of 40 s or more count.
- In the second half of each stretch, Bob's sound playout target and
  network-driven minimum per stats interval (as e7_video_calls.playout:
  W3C webrtc-stats jitterBufferTargetDelay and jitterBufferMinimumDelay,
  differences over jitterBufferEmittedCount), medians.
- Held: the target's median more than 100 ms above the minimum's. The
  minimum was 40-100 ms on P1 (calls28-31); the holds seen were 466-1,375.
- Tap to picture: from Alice's video-retry-tapped to the first stats line
  where Bob's video framesDecoded has grown.

One line per call. usage: python3 e7_off_hold.py OUT.jsonl LABEL..."""
import json
import os
import statistics
import sys
from datetime import datetime

MIN_OFF_S = 40
HELD_MS = 100


def events(path):
    for line in open(path):
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if "event" in e and "t" in e:
            e["at"] = datetime.fromisoformat(e["t"].replace("Z", "+00:00")).timestamp()
            yield e


def inbound(e, kind):
    for x in e["reports"]:
        if x["type"] == "inbound-rtp" and x.get("kind") == kind:
            return x
    return None


def playout(stats):
    """(time, target ms, minimum ms) per stats interval of Bob's sound."""
    pts = []
    for e in stats:
        x = inbound(e, "audio")
        if x:
            pts.append((e["at"], x["jitterBufferTargetDelay"], x["jitterBufferMinimumDelay"],
                        x["jitterBufferEmittedCount"]))
    return [(b[0], 1000 * (b[1] - a[1]) / (b[3] - a[3]), 1000 * (b[2] - a[2]) / (b[3] - a[3]))
            for a, b in zip(pts, pts[1:]) if b[3] > a[3]]


if __name__ == "__main__":
    with open(sys.argv[1], "a") as out:
        for label in sys.argv[2:]:
            for line in open(os.path.join("results", f"{label}.jsonl")):
                r = json.loads(line)
                if "profile" not in r:
                    continue
                d = os.path.join("results", label, r["profile"])
                alice = list(events(os.path.join(d, "alice.jsonl")))
                bob = list(events(os.path.join(d, "bob.jsonl")))
                stats = [e for e in bob if e["event"] == "stats"]
                pl = playout(stats)
                end = stats[-1]["at"] if stats else None
                sends = [e for e in alice if e["event"] == "video-sending"]
                stretches = []
                for i, e in enumerate(sends):
                    if e["sending"]:
                        continue
                    stop = e["at"]
                    back = next((s["at"] for s in sends[i + 1:] if s["sending"]), end)
                    if back is None or back - stop < MIN_OFF_S:
                        continue
                    half = [(t, m) for at, t, m in pl if stop + (back - stop) / 2 <= at <= back]
                    if not half:
                        continue
                    target = statistics.median(t for t, _ in half)
                    minimum = statistics.median(m for _, m in half)
                    stretches.append({"stop": e["t"][11:19], "off_s": round(back - stop),
                                      "target_ms": round(target), "minimum_ms": round(minimum),
                                      "held": target - minimum > HELD_MS})
                taps = []
                for e in alice:
                    if e["event"] != "video-retry-tapped":
                        continue
                    before = None
                    for s in stats:
                        v = inbound(s, "video")
                        n = (v or {}).get("framesDecoded") or 0
                        if s["at"] < e["at"]:
                            before = n
                        elif before is not None and n > before:
                            taps.append(round(s["at"] - e["at"], 1))
                            break
                    else:
                        taps.append(None)
                out.write(json.dumps({
                    "run": label, "profile": r["profile"],
                    "separate": (r.get("opus") or {}).get("separate-streams"),
                    "exits": [r.get("alice_exit"), r.get("bob_exit")],
                    "stretches": stretches,
                    "held": sum(s["held"] for s in stretches),
                    "tap_to_picture_s": taps,
                }) + "\n")
                out.flush()
