#!/usr/bin/env python3
"""E5: our calls against WhatsApp's Gate 1 numbers, by the rules fixed in
docs/GATE2-CALLS-PLAN.md (E5 plan) before any run.

    python3 lab/e5/table.py [--name=NAME] [--no-whatsapp] e5r1 e5r2 e5r3

Reads lab/gate2/results/<label>.jsonl (calls.py's summary lines) and each
call's voice_delay.jsonl and alice.jsonl; writes lab/e5/results/table.jsonl
(one line per profile, flushed) and lab/e5/results/TABLE.md.
"""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GATE2 = os.path.join(HERE, "..", "gate2", "results")
SETUP_DEADLINE_S = 90
# GATE1.md, WhatsApp baseline results table. None: no WhatsApp number.
WA = {"P1": {"voice_ms": 696, "frozen": 14.2}, "P2": {"voice_ms": None, "frozen": 3.4},
      "P3": {"voice_ms": None, "frozen": 6.0}}
ORDER = ["P1", "P2", "P3", "P4", "P5", "P0", "P1-blocked", "P2-blocked", "P3-blocked", "P4-blocked"]


def med(xs):
    xs = [x for x in xs if x is not None]
    return statistics.median(xs) if xs else None


def utc(text):
    sys.path.insert(0, os.path.join(HERE, "..", "gate2"))
    from labkit import utc as u
    return u(text)


def clicks_after_reconnect(d):
    """Clicks Bob heard that were sent after Alice's first reconnection."""
    try:
        ev = [json.loads(l) for l in open(os.path.join(d, "alice.jsonl"))]
        clicks = [json.loads(l) for l in open(os.path.join(d, "voice_delay.jsonl"))]
    except FileNotFoundError:
        return None
    back = [utc(e["t"]) for e in ev if e.get("event") == "reconnected"]
    if not back:
        return 0
    return sum(1 for c in clicks if c["sent"] > back[0] and c.get("delay_ms") is not None)


def row(profile, calls, judge=True):
    base = profile.split("-")[0]
    r = {"profile": profile, "calls": len(calls)}
    a = [c.get("alice") or {} for c in calls]
    r["connected"] = [x.get("connected") for x in a]
    r["route"] = [x.get("route") for x in a]
    r["ended"] = [x.get("ended") for x in a]
    r["connect_ms"] = [x.get("connect-ms") for x in a]
    r["frozen_s_per_min"] = [(c.get("recording_bob") or {}).get("frozen_s_per_min") for c in calls]
    r["voice_median_ms"] = [(c.get("voice") or {}).get("delay_median_ms") for c in calls]
    r["clicks_heard"] = [f"{(c.get('voice') or {}).get('clicks_heard')}/{(c.get('voice') or {}).get('clicks_sent')}"
                         for c in calls]
    r["fingerprint_hits"] = [c.get("fingerprint_hits") for c in calls]
    r["med_connect_ms"] = med(r["connect_ms"])
    r["med_frozen"] = med(r["frozen_s_per_min"])
    r["med_voice_ms"] = med(r["voice_median_ms"])
    verdict = {}
    # Connect time: WhatsApp's is unknown (lab/e5/results/whatsapp_connect.jsonl).
    verdict["connect"] = "no WhatsApp number"
    wa = WA.get(base) if not profile.endswith("-blocked") else WA.get(base)
    if wa and base in ("P1", "P2", "P3"):
        if wa["voice_ms"] is None:
            verdict["voice"] = "no WhatsApp number"
        else:
            verdict["voice"] = (None if r["med_voice_ms"] is None
                                else ("pass" if r["med_voice_ms"] <= wa["voice_ms"] else "fail"))
        verdict["frozen"] = (None if r["med_frozen"] is None
                             else ("pass" if r["med_frozen"] <= wa["frozen"] else "fail"))
    if base == "P4":
        after = [clicks_after_reconnect(c["_dir"]) for c in calls]
        r["clicks_after_first_reconnect"] = after
        ok = [x.get("ended") == "hangup" and (n or 0) >= 1 for x, n in zip(a, after)]
        verdict["survives_drop"] = f"{sum(ok)} of {len(ok)}"
    if base == "P5":
        verdict["connects"] = f"{sum(1 for x in a if x.get('connected'))} of {len(a)}"
    if base == "P0":
        ok = []
        for c in calls:
            x = c.get("alice") or {}
            ok.append(not x.get("connected") and c.get("alice_exit") not in (None, "")
                      and (c.get("alice_wall_s") or 1e9) <= SETUP_DEADLINE_S + 30)
        r["alice_wall_s"] = [c.get("alice_wall_s") for c in calls]
        r["alice_exit"] = [c.get("alice_exit") for c in calls]
        r["alice_ended"] = [(c.get("alice") or {}).get("ended") for c in calls]
        verdict["gives_up_cleanly"] = f"{sum(ok)} of {len(ok)}"
    r["verdict"] = verdict if judge else {"reported": "no WhatsApp counterpart"}
    return r


def main():
    labels = sys.argv[1:]
    name, judge = "table", True
    while labels and labels[0].startswith("--"):
        opt = labels.pop(0)
        if opt.startswith("--name="):
            name = opt[len("--name="):]
        elif opt == "--no-whatsapp":
            judge = False
    by = {}
    for lab in labels:
        for l in open(os.path.join(GATE2, f"{lab}.jsonl")):
            c = json.loads(l)
            if "profile" in c:
                c["_dir"] = os.path.join(GATE2, lab, c["profile"])
                by.setdefault(c["profile"], []).append(c)
    out = open(os.path.join(HERE, "results", f"{name}.jsonl"), "w")
    md = ["| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |",
          "|---|---|---|---|---|---|---|---|"]
    for p in ORDER:
        if p not in by:
            continue
        r = row(p, by[p], judge)
        out.write(json.dumps(r) + "\n")
        out.flush()
        print(json.dumps(r), flush=True)
        md.append(f"| {p} | {r['calls']} | {', '.join(str(x) for x in r['route'])} | "
                  f"{r['connect_ms']} ({r['med_connect_ms']}) | {r['frozen_s_per_min']} ({r['med_frozen']}) | "
                  f"{r['voice_median_ms']} ({r['med_voice_ms']}) | {', '.join(r['clicks_heard'])} | "
                  f"{'; '.join(f'{k}: {v}' for k, v in r['verdict'].items())} |")
    with open(os.path.join(HERE, "results", "TABLE.md" if name == "table" else f"{name}.md"), "w") as f:
        f.write("\n".join(md) + "\n")


if __name__ == "__main__":
    main()
