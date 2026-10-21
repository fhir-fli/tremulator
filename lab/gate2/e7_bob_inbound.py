"""Run from lab/gate2. Bob's inbound audio over the whole call, for calls26 P1 direct, control vs dropped fields."""
import json, sys
OUT = sys.argv[1]
KEYS = ["packetsReceived", "packetsLost", "packetsDiscarded", "fecPacketsReceived",
        "concealedSamples", "silentConcealedSamples", "concealmentEvents",
        "insertedSamplesForDeceleration", "removedSamplesForAcceleration",
        "interruptionCount", "totalInterruptionDuration", "jitterBufferFlushes",
        "totalSamplesReceived"]
with open(OUT, "w") as out:
    for prof in ["P1", "P1-blocked"]:
        for r in [1, 2, 3]:
            for arm in ["fc", "fd"]:
                d = f"results/calls26{r}{arm}/{prof}"
                last = None; tgt = []; jb = []
                for line in open(f"{d}/bob.jsonl"):
                    try: e = json.loads(line)
                    except json.JSONDecodeError: continue
                    if e.get("event") != "stats": continue
                    for x in e["reports"]:
                        if x["type"] == "inbound-rtp" and x.get("kind") == "audio":
                            if last:
                                de = x["jitterBufferEmittedCount"] - last["jitterBufferEmittedCount"]
                                if de > 0:
                                    jb.append(round(1000 * (x["jitterBufferDelay"] - last["jitterBufferDelay"]) / de))
                            last = x
                row = {"run": f"{r}{arm}", "profile": prof}
                row.update({k: last.get(k) for k in KEYS})
                n = last["totalSamplesReceived"]
                row["concealed_pct"] = round(100 * last["concealedSamples"] / n, 2)
                row["loss_pct"] = round(100 * last["packetsLost"] / (last["packetsLost"] + last["packetsReceived"]), 2)
                jb.sort()
                row["jb_ms_p50_p95_max"] = [jb[len(jb)//2], jb[int(len(jb)*.95)], jb[-1]] if jb else None
                out.write(json.dumps(row) + "\n"); out.flush()
