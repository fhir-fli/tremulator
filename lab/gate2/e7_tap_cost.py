"""Run from lab/gate2. What a "try video again" tap costs in late voice on
a weak relayed link (D17's open point: calls31 saw each video burst on
P1-blocked leave the network needing 1.0-1.6 s of sound buffer for 1-2
minutes). Method, fixed before calls33 was read (2026-11-03):

- Calls in pairs, same build, separate streams (the default), P1-blocked:
  one where the lab taps 60 s after each stop of Alice's video, one where
  nobody taps (video stays off after the phone stops it).
- From Alice's first video-sending false to the call's last stats line,
  Bob's sound playout target and network-driven minimum per stats interval
  (e7_off_hold.playout: W3C webrtc-stats jitterBufferTargetDelay and
  jitterBufferMinimumDelay over jitterBufferEmittedCount): medians, and
  the share of intervals with the target over 1,000 ms.
- Voice delay median from the clicks (calls.py's `voice`), whole call.
- Prediction: the tap arm's target median is more than 300 ms above its
  pair's in every pair. If it is within 300 ms in any pair, a tap does not
  measurably cost late voice there.

One line per call. usage: python3 e7_tap_cost.py OUT.jsonl LABEL..."""
import json
import os
import statistics
import sys

from e7_off_hold import events, playout

SLOW_MS = 1000


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
            stop = next((e["at"] for e in alice
                         if e["event"] == "video-sending" and not e["sending"]), None)
            pl = [(at, t, m) for at, t, m in playout(stats) if stop is not None and at >= stop]
            opus = r.get("opus") or {}
            out.write(json.dumps({
                "run": label, "profile": r["profile"],
                "tap_after": opus.get("tap-video-after"),
                "separate": opus.get("separate-streams"),
                "exits": [r.get("alice_exit"), r.get("bob_exit")],
                "taps": sum(e["event"] == "video-retry-tapped" for e in alice),
                "stops": sum(e["event"] == "video-sending" and not e["sending"] for e in alice),
                "after_stop_s": round(stats[-1]["at"] - stop) if pl else None,
                "target_ms": round(statistics.median(t for _, t, _ in pl)) if pl else None,
                "minimum_ms": round(statistics.median(m for _, _, m in pl)) if pl else None,
                "target_over_1s": round(sum(t > SLOW_MS for _, t, _ in pl) / len(pl), 2) if pl else None,
                "voice_median_ms": (r.get("voice") or {}).get("delay_median_ms"),
            }) + "\n")
            out.flush()
