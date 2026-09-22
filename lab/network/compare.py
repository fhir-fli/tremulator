#!/usr/bin/env python3
"""Gate 1 network verdict from results/run1.jsonl, results/run2.jsonl and the
P0 reruns. Pre-registered criteria (docs/GATE1.md): each check passes in both
runs, and run 2 is within ±10% of run 1 on every metric. For loss, a
two-proportion z-test is also reported, labelled as a secondary analysis; it
does not replace the ±10% criterion. Writes results/gate1_network_verdict.json."""
import json, math
def load(p): return [json.loads(l) for l in open(p)]
r1, r2 = load("results/run1.jsonl"), load("results/run2.jsonl")
key = lambda r: (r["profile"], r["metric"])
a, b = {key(r): r for r in r1}, {key(r): r for r in r2}
val = {"rtt_ms": "median", "delivered_bps": "bps", "loss": "measured_pct"}
rows, allok = [], True
for k in sorted(set(a) | set(b)):
    x, y = a.get(k), b.get(k)
    row = {"profile": k[0], "metric": k[1], "run1_pass": x and x["pass"], "run2_pass": y and y["pass"]}
    if k[1] in val and x and y and x.get(val[k[1]]) is not None and y.get(val[k[1]]) is not None:
        v1, v2 = x[val[k[1]]], y[val[k[1]]]
        row.update({"run1": round(v1, 3), "run2": round(v2, 3)})
        if v1 == 0 and v2 == 0: row["within_10pct"] = True
        else: row["rel_diff_pct"] = round(100 * (v2 - v1) / v1, 1) if v1 else None; row["within_10pct"] = v1 != 0 and abs(v2 - v1) <= 0.10 * abs(v1)
        if k[1] == "loss":
            n1, l1, n2, l2 = x["packets"], x["lost"], y["packets"], y["lost"]
            p = (l1 + l2) / (n1 + n2)
            se = math.sqrt(p * (1 - p) * (1/n1 + 1/n2)) if 0 < p < 1 else 0
            row["secondary_two_prop_z"] = round((l2/n2 - l1/n1) / se, 2) if se else 0.0
    if k[1] == "duty_cycle":
        row.update({"run1": x and x.get("up_windows_s"), "run2": y and y.get("up_windows_s")})
    ok = bool(row["run1_pass"]) and bool(row["run2_pass"]) and row.get("within_10pct", True)
    row["verdict"] = "PASS" if ok else "FAIL"; allok &= ok
    rows.append(row)
p0 = [json.loads(l) for f in ("results/p0-a.jsonl", "results/p0-b.jsonl") for l in open(f)]
p0ok = all(r["pass"] for r in p0)
allok &= p0ok
verdict = {"all_pass": allok, "p0_reruns_pass": [r["pass"] for r in p0], "rows": rows}
json.dump(verdict, open("results/gate1_network_verdict.json", "w"), indent=1)
for r in rows:
    print(f"{r['profile']:3} {r['metric']:28} run1={str(r.get('run1')):>22} run2={str(r.get('run2')):>22} "
          f"diff={str(r.get('rel_diff_pct','')):>6}% z={str(r.get('secondary_two_prop_z','')):>5} {r['verdict']}", flush=True)
print("P0 reruns:", [r["pass"] for r in p0], "| ALL PASS:", allok, flush=True)
