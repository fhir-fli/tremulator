#!/usr/bin/env python3
"""Video packets Alice sends while her video encoding is inactive (no frame
encoded since the last stats sample): count, and header bytes (payload is 0
for padding-only packets), per call, from alice.jsonl stats.

    cd lab/gate2/results && python3 ../../e5/idle_video_packets.py LABEL...
"""
import json,sys
for lab in sys.argv[1:]:
  for prof in ["P1","P1-blocked","P2","P2-blocked","P3","P3-blocked"]:
    try: L=[json.loads(l) for l in open(f"{lab}/{prof}/alice.jsonl")]
    except FileNotFoundError: continue
    prev=None; pk=0; hb=0; pb=0
    for e in L:
      if e.get("event")!="stats": continue
      v=[x for x in e["reports"] if x["type"]=="outbound-rtp" and x.get("kind")=="video"]
      if not v: continue
      x=v[0]
      cur=(x.get("packetsSent",0),x.get("headerBytesSent",0),x.get("bytesSent",0),x.get("framesEncoded",0),x.get("active"))
      if prev and not cur[4] and cur[3]==prev[3]:
        pk+=cur[0]-prev[0]; hb+=cur[1]-prev[1]; pb+=cur[2]-prev[2]
      prev=cur
    print(lab,prof.ljust(10),"idle video packets",pk,"header bytes",hb,"payload bytes",pb,flush=True)
