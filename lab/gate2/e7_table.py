#!/usr/bin/env python3
"""The E7 table (video gives way to sound): one row per run and profile,
from each profile's summary line and Alice's raw log.

    python3 -I lab/gate2/e7_table.py calls18 calls18d calls19a ...

Columns: the Opus parameters both phones asked for (RFC 7587), where the
relay sat, the route; clicks heard of sent with the voice delay (median,
min, max) and the median of the last five clicks heard (the queue may drain
during a call); Alice's sound as sent (payload kbit/s; all-in kbit/s =
payload + RTP headers + 28 bytes of IP and UDP per packet, without the SRTP
tag; packets per second; Opus's target) from stats line 40 to the last;
the round trip at 60, 150 and 290 s of stats; for each phone, everything
it put on the wire (the transport's bytes, all streams, RTCP and checks)
from stats line 40 to the last, its audio header bytes per packet (W3C
webrtc-stats headerBytesSent: "RTP header and padding bytes") and its most
audio packets in one second (padding bursts); Alice's video stopping and
starting (seconds after connected, sending, round trip) and when Bob was
told; reconnects; fingerprint hits in the server's data; exits.
"""
import json
import os
import statistics
import sys
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))


def ts(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp()


def stats_lines(path):
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path):
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("event") == "stats":
            out.append(e)
    return out


def sound(stats):
    pts = []
    for e in stats:
        for r in e["reports"]:
            if r["type"] == "outbound-rtp" and r.get("kind") == "audio":
                pts.append((e["t"], r["bytesSent"], r.get("headerBytesSent", 0),
                            r["packetsSent"], r.get("targetBitrate")))
    if len(pts) < 42:
        return None
    (t0, b0, h0, n0, _), (t1, b1, h1, n1, target) = pts[40], pts[-1]
    dt = ts(t1) - ts(t0)
    return {"payload_kbps": round((b1 - b0) * 8 / dt / 1000, 1),
            "all_in_kbps": round(((b1 - b0) + (h1 - h0) + 28 * (n1 - n0)) * 8 / dt / 1000, 1),
            "pps": round((n1 - n0) / dt, 1), "target": target}


def rtts(stats, at=(60, 150, 290)):
    out = {}
    for i, e in enumerate(stats, 1):
        if i in at:
            for r in e["reports"]:
                if r["type"] == "candidate-pair" and r.get("bytesSent", 0) > 1000:
                    out[i] = r.get("currentRoundTripTime")
    return out


def wire(stats):
    tr, au = [], []
    for e in stats:
        for r in e["reports"]:
            if r["type"] == "transport":
                tr.append((e["t"], r["bytesSent"]))
            if r["type"] == "outbound-rtp" and r.get("kind") == "audio":
                au.append((r["packetsSent"], r.get("headerBytesSent", 0)))
    if len(tr) < 42 or len(au) < 42:
        return None
    (t0, b0), (t1, b1) = tr[40], tr[-1]
    (n0, h0), (n1, h1) = au[40], au[-1]
    return {"wire_kbps": round((b1 - b0) * 8 / (ts(t1) - ts(t0)) / 1000, 1),
            "audio_hdr_B": round((h1 - h0) / max(n1 - n0, 1), 1),
            "most_pps": max(b[0] - a[0] for a, b in zip(au, au[1:]))}


def last_five(d):
    p = os.path.join(d, "voice_delay.jsonl")
    if not os.path.exists(p):
        return None
    heard = [json.loads(l)["delay_ms"] for l in open(p)]
    heard = [x for x in heard if x is not None][-5:]
    return round(statistics.median(heard)) if heard else None


def row(label, rec):
    d = os.path.join(HERE, "results", label, rec["profile"])
    stats = stats_lines(os.path.join(d, "alice.jsonl"))
    bob_stats = stats_lines(os.path.join(d, "bob.jsonl"))
    v, a, b = rec.get("voice") or {}, rec.get("alice") or {}, rec.get("bob") or {}
    return {
        "run": label, "profile": rec["profile"], "opus": rec.get("opus"),
        "speech": rec.get("speech"), "relay_link": rec.get("relay_link"),
        "route": a.get("route"),
        "clicks": f"{v.get('clicks_heard')}/{v.get('clicks_sent')}",
        "delay_ms": [v.get("delay_median_ms"), v.get("delay_min_ms"), v.get("delay_max_ms")],
        "last5_ms": last_five(d),
        "alice_sound": sound(stats),
        "wire": {"alice": wire(stats), "bob": wire(bob_stats)},
        "rtt_s": rtts(stats),
        "video": a.get("video-sending"), "bob_told": b.get("remote-video"),
        "reconnecting": [a.get("reconnecting"), b.get("reconnecting")],
        "ended": [a.get("ended"), b.get("ended")],
        "fingerprint_hits": rec.get("fingerprint_hits"),
        "exits": [rec.get("alice_exit"), rec.get("bob_exit")],
    }


def main():
    for label in sys.argv[1:]:
        for line in open(os.path.join(HERE, "results", f"{label}.jsonl")):
            rec = json.loads(line)
            if "profile" in rec:
                print(json.dumps(row(label, rec)), flush=True)


if __name__ == "__main__":
    main()
