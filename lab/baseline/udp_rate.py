#!/usr/bin/env python3
"""UDP bytes to and from the shaped phone (10.42.0.x), per 30 s, from a Gate 1
capture: shows which calls were on the shaped path and how full each
direction ran.

    cd lab/baseline && python3 udp_rate.py results/p1.pcap > results/p1_udp_rate_30s.txt
"""
import datetime, struct, sys
f = open(sys.argv[1], "rb"); f.read(24)
bins = {}; first = last = None
while True:
    h = f.read(16)
    if len(h) < 16: break
    ts, tu, cl, ol = struct.unpack("<IIII", h); d = f.read(cl)
    t = ts + tu / 1e6; first = first or t; last = t
    if d[12:14] != b"\x08\x00": continue
    ip = d[14:]
    if len(ip) < 28 or ip[9] != 17: continue
    up = ".".join(map(str, ip[12:16])).startswith("10.42.")
    k = (int(t // 30) * 30, "up" if up else "down")
    bins[k] = bins.get(k, 0) + ol
print("capture", datetime.datetime.fromtimestamp(first), datetime.datetime.fromtimestamp(last), flush=True)
for (t, dr), b in sorted(bins.items()):
    print(datetime.datetime.fromtimestamp(t).strftime("%H:%M:%S"), dr, round(b * 8 / 30 / 1000, 1), flush=True)
