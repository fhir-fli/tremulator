#!/usr/bin/env python3
"""What Alice puts on her uplink, by kind, per 4 s from connect: STUN (ICE
checks and TURN), RTP by payload type, RTCP, other (DTLS, data channel),
kbit/s including IP and UDP headers, per destination. Reads the lab's
<phone>_media.pcap (96-byte snap) directly. TURN channel data (first byte
0x40-0x4f) is unwrapped 4 bytes before classifying.

    cd lab/gate2/results && python3 ../../e5/pcap_kinds.py LABEL/PROFILE [until_s]
"""
import struct,sys,json,collections
from datetime import datetime
rp=sys.argv[1]; until=float(sys.argv[2]) if len(sys.argv)>2 else 24
L=[json.loads(l) for l in open(f"{rp}/alice.jsonl")]
t0=datetime.fromisoformat([e["t"] for e in L if e.get("event")=="connected"][0].replace("Z","+00:00")).timestamp()
f=open(f"{rp}/g2c-alice_media.pcap","rb"); f.read(24)
b=collections.defaultdict(collections.Counter)
def kind(p):
  if not p: return "empty"
  c=p[0]
  if c in (0,1): return "stun"
  if 0x40<=c<=0x4f: return "turn-ch:"+kind(p[4:])
  if 20<=c<=63: return "dtls"
  if 128<=c<=191 and len(p)>1:
    pt=p[1]&0x7f
    return f"rtcp" if 72<=pt<=79 or 192<=p[1]<=223 else f"rtp{pt}"
  return f"other{c}"
while True:
  h=f.read(16)
  if len(h)<16: break
  ts,us,incl,orig=struct.unpack("<IIII",h); d=f.read(incl)
  t=ts+us/1e6-t0
  if not -4<=t<until or d[12:14]!=b"\x08\x00": continue
  ip=d[14:]; ihl=(ip[0]&15)*4
  if ip[9]!=17: continue
  src=".".join(map(str,ip[12:16])); dst=".".join(map(str,ip[16:20]))
  if src!="172.18.0.4": continue
  udp=ip[ihl:]; dport=struct.unpack(">H",udp[2:4])[0]; ulen=struct.unpack(">H",udp[4:6])[0]
  b[int((t+4)//4)*4-4][f"{dst}:{dport} {kind(udp[8:])}"]+=ulen+20
for s in sorted(b): print(s, {k:f"{v*8/4000:.1f}k" for k,v in b[s].most_common(6)},flush=True)
