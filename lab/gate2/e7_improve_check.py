"""Run from lab/gate2. E7: video the engine held back on a weak link, when
the link gets better mid-call (calls_e7_improve.sh). Method and decision
rule, fixed before the run was read (2026-11-19):

Three calls, P1-blocked (relayed, field relay) improving to P2 120 s after
connect, 300 s calls, calls37's settings: <L>s1 the default build (suspend
on), <L>s0 --no-suspend-video (taps 60 s after each stop), <L>nv sound only
(--no-video), the voice-only reference on the same links.

- T: when the link changed, the earliest `<container>_improve.at`.
- Resume: Alice's first `video-held` false after T (the app's own notice),
  and, as a check that does not rely on it, her first stats interval after
  T in which outbound video framesEncoded grew. Seconds after T.
- Window: from T + W to the call's last stats line, W = <L>s1's resume
  seconds (30 s if it never resumed), the same offset in all three calls.
- In the window: voice delay median and clicks heard of sent (voice_delay
  .jsonl, by each click's send time); Bob's sound playout target median
  (e7_off_hold.playout); frames Bob decoded. The same before T, for the
  record.
- Decision (TS 26.114 V19.3.0 §10.3.5: raising quality must add no delay or
  loss): video coming back by itself costs the voice if, in the window,
  <L>s1's voice median is more than 100 ms above <L>nv's, or its playout
  target median more than 300 ms above (calls34's bar). The 100 ms is our
  bar, chosen before the run. One call per arm: a single pair.

One line per call. usage: python3 e7_improve_check.py OUT.jsonl L [arm=label ...]"""
import glob
import json
import os
import statistics
import sys

from e7_off_hold import events, inbound, playout

NO_RESUME_W = 30


def load(label):
    r = next(json.loads(l) for l in open(os.path.join("results", f"{label}.jsonl"))
             if '"profile"' in l)
    d = os.path.join("results", label, r["profile"])
    ats = [float(open(p).read()) for p in glob.glob(os.path.join(d, "*_improve.at"))]
    clicks = [json.loads(l) for l in open(os.path.join(d, "voice_delay.jsonl"))]
    return (r, list(events(os.path.join(d, "alice.jsonl"))),
            list(events(os.path.join(d, "bob.jsonl"))), min(ats) if ats else None, clicks)


def resume(alice, t):
    notice = next((e["at"] - t for e in alice if e["event"] == "video-held"
                   and not e["held"] and e["at"] > t), None)
    prev, grew = None, None
    for e in alice:
        if e["event"] != "stats":
            continue
        f = sum(x.get("framesEncoded", 0) for x in e["reports"]
                if x["type"] == "outbound-rtp" and x.get("kind") == "video")
        if prev is not None and e["at"] > t and f > prev:
            grew = e["at"] - t
            break
        prev = f
    return notice, grew


def window(r, alice, bob, clicks, lo, hi):
    stats = [e for e in bob if e["event"] == "stats"]
    sent = [c for c in clicks if lo <= c["sent"] < hi]
    heard = [c["delay_ms"] for c in sent if c["delay_ms"] is not None]
    pl = [t for at, t, _ in playout(stats) if lo <= at < hi]
    dec = [(inbound(e, "video") or {}).get("framesDecoded", 0) for e in stats if lo <= e["at"] < hi]
    return {"voice_median_ms": round(statistics.median(heard)) if heard else None,
            "voice_max_ms": max(heard) if heard else None,
            "clicks_heard": len(heard), "clicks_sent": len(sent),
            "target_ms": round(statistics.median(pl)) if pl else None,
            "bob_frames_decoded": (dec[-1] - dec[0]) if dec else None}


L = sys.argv[2]
# Arms default to <L>s1, <L>s0, <L>nv; `arm=label` after L names them
# (calls40: s1=calls40s1 nv=calls39nv, one new call against a kept one).
labels = dict(a.split("=", 1) for a in sys.argv[3:]) or {arm: f"{L}{arm}" for arm in ("s1", "s0", "nv")}
calls = {arm: load(label) for arm, label in labels.items()}
r1, a1, _, t1, _ = calls["s1"]
notice1, grew1 = resume(a1, t1) if t1 else (None, None)
w = notice1 if notice1 is not None else NO_RESUME_W
rows = {}
with open(sys.argv[1], "a") as out:
    for arm, (r, alice, bob, t, clicks) in calls.items():
        notice, grew = resume(alice, t) if t else (None, None)
        end = max(e["at"] for e in alice if e["event"] == "stats")
        row = {"check": "improve", "run": labels[arm], "profile": r["profile"],
               "improve": r.get("improve"), "exits": [r.get("alice_exit"), r.get("bob_exit")],
               "switched": t is not None,
               "resume_notice_s": None if notice is None else round(notice, 1),
               "resume_frames_s": None if grew is None else round(grew, 1),
               "taps_after_switch": sum(e["event"] == "video-retry-tapped" and t is not None
                                        and e["at"] > t for e in alice),
               "held_changes": [(round(e["at"] - t, 1) if t else None, e["held"])
                                for e in alice if e["event"] == "video-held"],
               "window_from_s": round(w, 1),
               "before": window(r, alice, bob, clicks, 0, t) if t else None,
               "after": window(r, alice, bob, clicks, t + w, end) if t else None}
        rows[arm] = row
        out.write(json.dumps(row) + "\n")
        out.flush()
        print(json.dumps(row), flush=True)
    a, b = rows["s1"]["after"], rows["nv"]["after"]
    costs = None
    if a and b and None not in (a["voice_median_ms"], b["voice_median_ms"],
                                 a["target_ms"], b["target_ms"]):
        costs = (a["voice_median_ms"] - b["voice_median_ms"] > 100
                 or a["target_ms"] - b["target_ms"] > 300)
    verdict = {"check": "improve-verdict", "run": L,
               "resumed_by_itself": rows["s1"]["resume_notice_s"] is not None
               and rows["s1"]["taps_after_switch"] == 0,
               "resume_costs_voice": costs}
    out.write(json.dumps(verdict) + "\n")
    out.flush()
    print(json.dumps(verdict), flush=True)
