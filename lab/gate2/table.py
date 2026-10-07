#!/usr/bin/env python3
"""Turn results/<label>.jsonl into the Gate 2 text table (markdown on stdout).

    python3 lab/gate2/table.py run1

The WhatsApp column is the Gate 1 baseline, docs/GATE1.md, 2026-10-05/06.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WHATSAPP = {  # profile: texts Android->iPhone, from the GATE1.md table
    "P1": "10/10, median 5.3 s",
    "P2": "10/10",
    "P3": "10/10, median 5.7 s, max 8.3 s",
    "P4": "10/10, 53–75 s when sent into an outage",
    "P5": "0 delivered (no internet, WhatsApp needs Meta)",
    "P0": "0 delivered",
}

label = sys.argv[1]
rows = [json.loads(l) for l in open(os.path.join(HERE, "results", f"{label}.jsonl"))]
print("| Profile | tremulator texts | one-way median | one-way max | failed sends | out of step | store readable? | WhatsApp (Gate 1) |")
print("|---|---|---|---|---|---|---|---|")
for r in rows:
    if "profile" not in r:
        continue
    med = f"{r['one_way_median_ms']/1000:.1f} s" if r.get("one_way_median_ms") is not None else "—"
    mx = f"{r['one_way_max_ms']/1000:.1f} s" if r.get("one_way_max_ms") is not None else "—"
    scan = "no (scan clean)" if r.get("canary_scan_exit") == 0 else f"HITS: {r.get('canary_hits')}"
    print(f"| {r['profile']} | {r['delivered']}/{r['sent']} | {med} | {mx} | {r['send_failed']} | {r['out_of_step']} | {scan} | {WHATSAPP.get(r['profile'], '')} |")
