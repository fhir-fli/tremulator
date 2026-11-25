#!/usr/bin/env python3
"""Per call: Alice's outgoing bandwidth estimate (kbit/s, nominated pair),
median over each 30 s of the call, and the frames Bob decoded. Asks whether
the estimate stays low for the whole call when video freezes.

    cd lab/gate2/results && python3 ../../e5/whole_call_estimate.py LABEL...
"""
import json,sys,statistics
from datetime import datetime
def ts(s): return datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
profiles=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else ["P1","P1-blocked","P2","P2-blocked","P3","P3-blocked"]
runs=sys.argv[1:sys.argv.index("--")] if "--" in sys.argv else sys.argv[1:]
for r in runs:
  rows={json.loads(l)["profile"]:json.loads(l) for l in open(f"{r}.jsonl") if '"alice"' in l}
  for p in profiles:
    try: L=[json.loads(l) for l in open(f"{r}/{p}/alice.jsonl")]
    except FileNotFoundError: continue
    c=[ts(e["t"]) for e in L if e.get("event")=="connected"]
    if not c: print(r,p,"| not connected",flush=True); continue
    t0=c[0]; bins={}
    for e in L:
      if e.get("event")!="stats": continue
      t=ts(e["t"])-t0
      for x in e["reports"]:
        if x["type"]=="candidate-pair" and x.get("nominated") and x.get("availableOutgoingBitrate"):
          bins.setdefault(int(t//30)*30,[]).append(x["availableOutgoingBitrate"]/1000)
    est=" ".join(f"{k}s:{statistics.median(v):.0f}" for k,v in sorted(bins.items()))
    d=rows.get(p,{})
    print(f"{r} {p:10} | {est} | bob frames {d.get('bob',{}).get('video-frames-decoded')} frozen/min {d.get('recording_bob',{}).get('frozen_s_per_min')}",flush=True)
