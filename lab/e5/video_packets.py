#!/usr/bin/env python3
"""Alice's video packets per call, from her own stats (alice.jsonl): total,
and over the last two thirds of the call (video is off by then in P1).

    cd lab/gate2/results && python3 ../../e5/video_packets.py LABEL...
"""
import json,sys
for lab in sys.argv[1:]:
  for prof in ["P1","P1-blocked","P2","P3"]:
    try: lines=[json.loads(l) for l in open(f"{lab}/{prof}/alice.jsonl")]
    except FileNotFoundError: continue
    st=[r for r in lines if r.get("event")=="stats"]
    def vid(r):
        for x in r["reports"]:
            if x["type"]=="outbound-rtp" and x.get("kind")=="video":
                return x.get("packetsSent",0), x.get("headerBytesSent",0)+x.get("bytesSent",0), x.get("framesSent",0), x.get("active")
        return 0,0,0,None
    v=[vid(r) for r in st]
    # last 100 stats samples ~ period with video off typically
    n=len(v); a=v[n//3]; b=v[-1]
    print(lab, prof.ljust(10), "samples", n, "video pk", v[-1][0], "bytes", v[-1][1], "frames", v[-1][2], "| last 2/3: pk", b[0]-a[0], "bytes", b[1]-a[1], "frames", b[2]-a[2], "active", b[3])
