"""Run from lab/gate2. For each click in calls26 P1 runs: Bob's concealed samples (ms of audio made up) in the
stats interval(s) covering where the click should have played, missed vs heard."""
import json, statistics, sys
from datetime import datetime
OUT = sys.argv[1]
ts = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()
lv = {}
for l in open(sys.argv[2]):
    r = json.loads(l); lv[(r["profile"], r["run"], r["click"])] = r["fraction"]
with open(OUT, "w") as out:
    for prof in ["P1", "P1-blocked"]:
        for r in [1, 2, 3]:
            for arm in ["fc", "fd"]:
                d = f"results/calls26{r}{arm}/{prof}"
                pts = []
                for line in open(f"{d}/bob.jsonl"):
                    try: e = json.loads(line)
                    except json.JSONDecodeError: continue
                    if e.get("event") != "stats": continue
                    for x in e["reports"]:
                        if x["type"] == "inbound-rtp" and x.get("kind") == "audio":
                            pts.append((ts(e["t"]), x["concealedSamples"], x["insertedSamplesForDeceleration"], x["removedSamplesForAcceleration"]))
                rows = [json.loads(l) for l in open(f"{d}/voice_delay.jsonl")]
                med = statistics.median([x["delay_ms"] for x in rows if x["delay_ms"] is not None]) / 1000
                for i, x in enumerate(rows):
                    at = x["sent"] + (med if x["delay_ms"] is None else x["delay_ms"] / 1000)
                    j = next((k for k, p in enumerate(pts) if p[0] >= at), None)
                    if j is None or j + 1 >= len(pts) or j == 0: continue
                    # the interval holding `at` and the one after (stats lag)
                    a, b = pts[j - 1], pts[j + 1]
                    out.write(json.dumps({"profile": prof, "run": f"{r}{arm}", "click": i,
                        "missed": x["delay_ms"] is None, "fraction": lv[(prof, f"{r}{arm}", i)],
                        "concealed_ms": round((b[1] - a[1]) / 48), "decel_ms": round((b[2] - a[2]) / 48),
                        "accel_ms": round((b[3] - a[3]) / 48), "span_s": round(b[0] - a[0], 1)}) + "\n")
                    out.flush()
