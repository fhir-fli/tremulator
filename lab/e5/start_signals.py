#!/usr/bin/env python3
"""Per call: Alice's video events (guard start/stop, engine hold/release, s
after connect) and WebRTC's outgoing bandwidth estimate (kbit/s, nominated
pair) every 3 s over the first 30 s. Asks whether a bandwidth floor at the
guard's start, or stopping on a hold, separates P1 from P2.

    cd lab/gate2/results && python3 ../../e5/start_signals.py LABEL...
"""
import json,sys
from datetime import datetime
def ts(s): return datetime.fromisoformat(s.replace("Z","+00:00")).timestamp()
for r in sys.argv[1:]:
  for p in ["P1","P1-blocked","P2","P2-blocked","P3","P3-blocked","P4","P4-blocked"]:
    try: L=[json.loads(l) for l in open(f"{r}/{p}/alice.jsonl")]
    except FileNotFoundError: continue
    c=[ts(e["t"]) for e in L if e.get("event")=="connected"]
    if not c: print(r,p,"| not connected",flush=True); continue
    t0=c[0]; out=[]
    for e in L:
      ev=e.get("event")
      if ev in("video-held","video-sending"):
        out.append(f"{ev[6:]}={e.get('held',e.get('sending'))}@{ts(e['t'])-t0:.0f}")
      if ev=="stats":
        t=ts(e["t"])-t0
        for x in e["reports"]:
          if x["type"]=="candidate-pair" and x.get("nominated") and x.get("availableOutgoingBitrate") and t<=30 and int(t)%3==0:
            out.append(f"{t:.0f}s:{x['availableOutgoingBitrate']/1000:.0f}")
    print(r,p,"|"," ".join(out),flush=True)
