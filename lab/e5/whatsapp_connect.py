#!/usr/bin/env python3
"""E5: can WhatsApp's connect time be read from the Gate 1 files?

    python3 lab/e5/whatsapp_connect.py lab/e5/results/whatsapp_connect.jsonl

For each Gate 1 call with a tap record (lab/baseline/results/
android_<call>_call.jsonl, the laptop's clock, as baseline_android.dart
logs it), the phone's UDP to and from Meta's relay port 3478 in the
laptop's hotspot capture (p<n>.pcap, same clock): when the first packet
went out and came back, and packets per second each way for 40 s after
the tap. One JSON line per call, flushed.

What it cannot give: the moment the call was answered. The iPhone was
answered by hand and nothing logged when; the relay traffic starts while
the call rings, so its first packets are not media.
"""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "gate2"))
from media_pcap import packets  # noqa: E402

RES = os.path.join(HERE, "..", "baseline", "results")
CALLS = {"p1": "p1", "p1video": "p1", "p1video2": "p1", "p2video": "p2", "p3": "p3",
         "p3video": "p3", "p4": "p4", "p4b": "p4", "p4video": "p4"}
PHONE = "10.42.0."


def main():
    out = open(sys.argv[1], "a")
    for call, pc in CALLS.items():
        tap = next(json.loads(l) for l in open(os.path.join(RES, f"android_{call}_call.jsonl"))
                   if "call_tap" in l)
        t0 = tap["ms"] / 1000
        per_s = collections.defaultdict(lambda: [0, 0])
        first_out = first_in = None
        for t, src, dst, _ in packets(os.path.join(RES, f"{pc}.pcap")):
            if not t0 - 2 <= t <= t0 + 40:
                continue
            if src.startswith(PHONE) and dst.endswith(":3478"):
                per_s[int(t - t0)][0] += 1
                first_out = first_out if first_out is not None else round(t - t0, 2)
            elif dst.startswith(PHONE) and src.endswith(":3478"):
                per_s[int(t - t0)][1] += 1
                first_in = first_in if first_in is not None else round(t - t0, 2)
        rec = {"call": call, "kind": tap["kind"], "pcap": f"{pc}.pcap",
               "first_relay_out_s": first_out, "first_relay_in_s": first_in,
               "per_s_out_in": {s: v for s, v in sorted(per_s.items())}}
        out.write(json.dumps(rec) + "\n")
        out.flush()
        print(json.dumps({k: rec[k] for k in ("call", "first_relay_out_s", "first_relay_in_s")}), flush=True)


if __name__ == "__main__":
    main()
