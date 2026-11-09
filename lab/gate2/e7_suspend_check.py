"""Run from lab/gate2. Calls.suspendVideoBelowMinimum on a weak relayed
link (calls_e7_suspend.sh). Method, fixed before calls34 was read
(2026-11-09):

- From Alice's first video-sending true to the call's last stats line:
  Bob's sound playout target per stats interval (e7_off_hold.playout, W3C
  webrtc-stats jitterBufferTargetDelay over jitterBufferEmittedCount):
  median, and the share of intervals over 1,000 ms.
- While Alice's video is on (video-sending true until false), her video
  sent rate per stats interval (outbound-rtp video bytesSent +
  headerBytesSent): the share of intervals under 1 kbit/s ("suspended").
- Voice delay median from the clicks (calls.py's `voice`), whole call.
- Prediction: the option's target median is more than 300 ms below the
  call without it, and its suspended share is over 0.5. (Without the
  option the share is not zero: calls332t1 0.02, calls332t0 0.12, from
  intervals at a start or stop.)

One line per call. usage: python3 e7_suspend_check.py OUT.jsonl LABEL..."""
import json
import os
import statistics
import sys

from e7_off_hold import events, playout

SLOW_MS = 1000


def video_rates(alice):
    """(at, kbit/s, sending) per stats interval of Alice's video."""
    prev = None
    sending = False
    for e in alice:
        if e["event"] == "video-sending":
            sending = e["sending"]
        if e["event"] != "stats":
            continue
        b = sum(r.get("bytesSent", 0) + r.get("headerBytesSent", 0)
                for r in e["reports"]
                if r["type"] == "outbound-rtp" and r.get("kind") == "video")
        if prev is not None and e["at"] > prev[0]:
            yield e["at"], (b - prev[1]) * 8 / (e["at"] - prev[0]) / 1000, sending
        prev = (e["at"], b)


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
            start = next((e["at"] for e in alice
                          if e["event"] == "video-sending" and e["sending"]), None)
            pl = [(at, t, m) for at, t, m in playout(stats)
                  if start is not None and at >= start]
            on = [k for _, k, s in video_rates(alice) if s]
            opus = r.get("opus") or {}
            last = next((x for e in reversed(alice) if e["event"] == "stats"
                         for x in e["reports"]
                         if x["type"] == "outbound-rtp" and x.get("kind") == "video"), {})
            out.write(json.dumps({
                "check": "suspend", "run": label, "profile": r["profile"],
                "suspend": opus.get("suspend-video"),
                "exits": [r.get("alice_exit"), r.get("bob_exit")],
                "taps": sum(e["event"] == "video-retry-tapped" for e in alice),
                "stops": sum(e["event"] == "video-sending" and not e["sending"] for e in alice),
                "video_on_intervals": len(on),
                "suspended_share": round(sum(k < 1 for k in on) / len(on), 2) if on else None,
                "video_on_kbit_median": round(statistics.median(on), 1) if on else None,
                "target_ms": round(statistics.median(t for _, t, _ in pl)) if pl else None,
                "target_over_1s": round(sum(t > SLOW_MS for _, t, _ in pl) / len(pl), 2) if pl else None,
                "voice_median_ms": (r.get("voice") or {}).get("delay_median_ms"),
                "clicks_heard": (r.get("voice") or {}).get("clicks_heard"),
                "voice_max_ms": (r.get("voice") or {}).get("delay_max_ms"),
                "frames_encoded": last.get("framesEncoded"),
                "payload_bytes": last.get("bytesSent"),
            }) + "\n")
            out.flush()
            print(label, "done", flush=True)
