#!/usr/bin/env python3
"""Append hand-review decisions to dla_reviewed.tsv. Reads lines on stdin:
CODE<TAB>TRANSFER<TAB>VITAL<TAB>NOTE   TRANSFER in FREE|COND|AUTH|LOCAL
VITAL: yes = DLA's transfer text mentions a life / vital-interest / health
emergency exception; no = DLA does not mention one (not proof the law lacks it)."""
import csv, os, sys
path = "dla_reviewed.tsv"
new = not os.path.exists(path)
f = open(path, "a", newline="")
w = csv.writer(f, delimiter="\t")
if new:
    w.writerow(["code", "transfer_final", "vital_final", "review_note"]); f.flush()
ok = {"FREE", "COND", "AUTH", "LOCAL"}
n = 0
for line in sys.stdin:
    line = line.rstrip("\n")
    if not line.strip():
        continue
    code, tr, vit, note = (line.split("\t") + ["", "", ""])[:4]
    assert tr in ok, line
    assert vit in {"yes", "no"}, line
    w.writerow([code, tr, vit, note]); f.flush(); n += 1
print(f"recorded {n}", flush=True)
