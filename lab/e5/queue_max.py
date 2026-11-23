#!/usr/bin/env python3
"""Largest backlog (packets) of the shaping queue on each container's uplink,
from the lab's periodic `tc -s qdisc` dumps (*_qdisc.log, root netem only).

    cd lab/gate2/results && python3 ../../e5/queue_max.py LABEL...
"""
import re,sys,glob,os
for lab in sys.argv[1:]:
  for prof in ["P1","P1-blocked","P2","P2-blocked","P3","P3-blocked"]:
    out=[]
    for who in ["alice","bob"]:
      f=f"{lab}/{prof}/g2c-{who}_qdisc.log"
      if not os.path.exists(f): out.append(f"{who} -"); continue
      mx=0; root=False
      for line in open(f):
        if line.startswith("qdisc "): root=" root " in line and "netem" in line
        m=re.search(r"backlog \S+ (\d+)p",line)
        if m and root: mx=max(mx,int(m.group(1)))
      out.append(f"{who} {mx}")
    print(lab, prof.ljust(10), "max backlog packets:", ", ".join(out), flush=True)
