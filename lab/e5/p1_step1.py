#!/usr/bin/env python3
"""E5 follow-up step 1: does P1's voice delay go when there is no video
stream? Rule (docs/GATE2-CALLS-PLAN.md, fixed before the runs): the idea
holds if the round trip stays under 1 s and the voice median is at or
under WhatsApp's 696 ms, per profile over its three calls.

    python3 lab/e5/p1_step1.py e5nv1 e5nv2 e5nv3

Writes lab/e5/results/p1_step1.jsonl, one line per call then one per
profile, flushed. The same numbers for the E5 calls with video are written
too (labels e5r1 e5r2 e5r3 / e5r1b), as the comparison.
"""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GATE2 = os.path.join(HERE, "..", "gate2", "results")
WA_VOICE_MS = 696


def call_facts(label, rec):
    d = os.path.join(GATE2, label, rec["profile"])
    rtts, vpad = [], []
    prev = None
    for l in open(os.path.join(d, "alice.jsonl")):
        e = json.loads(l)
        if e.get("event") != "stats":
            continue
        for r in e["reports"]:
            if r["type"] == "candidate-pair" and isinstance(r.get("currentRoundTripTime"), (int, float)):
                rtts.append(r["currentRoundTripTime"])
    v = rec.get("voice") or {}
    return {"label": label, "profile": rec["profile"], "connected": (rec.get("alice") or {}).get("connected"),
            "ended": (rec.get("alice") or {}).get("ended"), "rtt_max_s": max(rtts) if rtts else None,
            "rtt_median_s": statistics.median(rtts) if rtts else None,
            "voice_median_ms": v.get("delay_median_ms"),
            "clicks": f"{v.get('clicks_heard')}/{v.get('clicks_sent')}"}


def main():
    out = open(os.path.join(HERE, "results", "p1_step1.jsonl"), "w")

    def emit(r):
        out.write(json.dumps(r) + "\n")
        out.flush()
        print(json.dumps(r), flush=True)

    groups = {"no-video": sys.argv[1:], "with-video (E5)": ["e5r1", "e5r2", "e5r3", "e5r1b"]}
    for name, labels in groups.items():
        by = {}
        for lab in labels:
            for l in open(os.path.join(GATE2, f"{lab}.jsonl")):
                rec = json.loads(l)
                if rec.get("profile") in ("P1", "P1-blocked"):
                    f = call_facts(lab, rec)
                    f["group"] = name
                    emit(f)
                    by.setdefault(rec["profile"], []).append(f)
        for p, fs in by.items():
            v = [f["voice_median_ms"] for f in fs if f["voice_median_ms"] is not None]
            rmax = [f["rtt_max_s"] for f in fs if f["rtt_max_s"] is not None]
            med = statistics.median(v) if v else None
            r = {"group": name, "profile": p, "calls": len(fs), "voice_median_ms": med,
                 "rtt_max_s": max(rmax) if rmax else None}
            if name == "no-video":
                r["idea_holds"] = bool(med is not None and med <= WA_VOICE_MS and rmax and max(rmax) < 1.0)
            emit(r)


if __name__ == "__main__":
    main()
