#!/usr/bin/env python3
"""Print a batch of DLA transfer sections for hand review. Usage: show_batch.py START END"""
import csv, json, sys
a, b = int(sys.argv[1]), int(sys.argv[2])
auto = list(csv.DictReader(open("dla_auto.tsv"), delimiter="\t"))
recs = {json.loads(l)["code"]: json.loads(l) for l in open("dla_sections.jsonl")}
for n, r in enumerate(auto[a:b], a + 1):
    tr = " ".join(recs[r["code"]]["sections"].get("Transfer of personal data", "").split())
    tr = tr.split(" ", 5)[-1] if tr.startswith("Transfer of personal data") else tr
    print(f"#{n} {r['code']} {r['name']} [{r['transfer_auto']}] vital={r['vital_auto']} health={r['health_sensitive_auto']} med={r['medical_basis_auto']}", flush=True)
    print("   " + tr[:520], flush=True)
