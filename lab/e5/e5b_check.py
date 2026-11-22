#!/usr/bin/env python3
"""Judges the E5b instrument check (e5b_check.sh). Passes when:
plus500's voice median is 400-600 ms above none's; Alice's round trip on
plus500 has a median of 0.9-1.2 s (500 ms each way on her link); on plus500
Alice's uplink and downlink each sent packets through netem and no other
machine has netem on eth0. Writes lab/e5/results/e5b_check.jsonl."""
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GATE2 = os.path.join(HERE, "..", "gate2", "results")


def main():
    lab = sys.argv[1]
    recs = {r["profile"]: r for r in map(json.loads, open(os.path.join(GATE2, f"{lab}.jsonl")))
            if "profile" in r}
    out = {}
    for p in ("none", "plus500"):
        r = recs[p]
        d = os.path.join(GATE2, lab, p)
        rtts = [x["currentRoundTripTime"] for l in open(os.path.join(d, "alice.jsonl"))
                for e in [json.loads(l)] if e.get("event") == "stats"
                for x in e["reports"] if x["type"] == "candidate-pair" and isinstance(x.get("currentRoundTripTime"), (int, float))]
        netem_on = {}
        for c in r["qdisc"]:
            text = open(os.path.join(d, f"{c}_qdisc.log")).read()
            netem_on[c] = "netem" in text
        out[p] = {"voice_median_ms": (r.get("voice") or {}).get("delay_median_ms"),
                  "clicks": f"{(r.get('voice') or {}).get('clicks_heard')}/{(r.get('voice') or {}).get('clicks_sent')}",
                  "rtt_median_s": statistics.median(rtts) if rtts else None,
                  "netem_on_eth0": netem_on, "uplink": r["qdisc"], "downlink": r.get("qdisc_in")}
    a = [c for c in out["plus500"]["netem_on_eth0"] if c.endswith("alice") or c.endswith("alice5")][0]
    v0, v1 = out["none"]["voice_median_ms"], out["plus500"]["voice_median_ms"]
    rtt = out["plus500"]["rtt_median_s"]
    down = (out["plus500"]["downlink"] or {}).get(a) or {}
    up = (out["plus500"]["uplink"] or {}).get(a) or {}
    checks = {
        "voice_plus_400_600": v0 is not None and v1 is not None and 400 <= v1 - v0 <= 600,
        "alice_rtt_0.9_1.2": rtt is not None and 0.9 <= rtt <= 1.2,
        "alice_uplink_through_netem": (up.get("sent_pkts") or 0) > 0,
        "alice_downlink_through_netem": (down.get("sent_pkts") or 0) > 0,
        "only_alice_has_netem": all(v == (c == a) for c, v in out["plus500"]["netem_on_eth0"].items()),
        "none_has_no_netem": not any(out["none"]["netem_on_eth0"].values()),
    }
    res = {"calls": out, "voice_difference_ms": (v1 - v0) if v0 is not None and v1 is not None else None,
           "checks": checks, "pass": all(checks.values())}
    with open(os.path.join(HERE, "results", "e5b_check.jsonl"), "a") as f:
        f.write(json.dumps(res) + "\n")
    print(json.dumps({"voice_difference_ms": res["voice_difference_ms"], "rtt_plus500": rtt,
                      "checks": checks, "pass": res["pass"]}), flush=True)
    sys.exit(0 if res["pass"] else 1)


if __name__ == "__main__":
    main()
