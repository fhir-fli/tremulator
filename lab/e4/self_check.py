#!/usr/bin/env python3
"""The relay scan under known conditions, before any lab call
(docs/GATE2-CALLS-PLAN.md E4; a clean result means nothing until the scan
has found what it looks for).

    python3 lab/e4/self_check.py OUT_DIR

ffmpeg sends the click track (9 clicks) as Opus RTP to a socket here; the
packets are written into pcap files as the relay would capture them:
1. plain, as UDP payloads: the scan must find the 9 clicks, in order;
2. the same wrapped in TURN ChannelData: the same 9;
3. the same with every payload byte after the RTP header replaced by random
   bytes (what SRTP's encryption leaves to anyone without the key): 0.
Writes OUT_DIR/self_check.jsonl, one line per case, flushed; exit 0 only
if all three hold.
"""
import json
import os
import random
import socket
import struct
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "gate2"))
import relay_scan  # noqa: E402
from voice_delay import call_track, coded  # noqa: E402


def capture(track):
    """The RTP packets ffmpeg sends for `track`."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("127.0.0.1", 0))
    sock.settimeout(3)
    port = sock.getsockname()[1]
    ff = subprocess.Popen(["ffmpeg", "-loglevel", "error", "-re", "-i", track, "-c:a", "libopus",
                           "-b:a", "32k", "-payload_type", "111", "-f", "rtp",
                           f"rtp://127.0.0.1:{port}?rtcpport={port + 1}"],
                          stdin=subprocess.DEVNULL)
    out = []
    try:
        while True:
            out.append(sock.recv(2048))
    except socket.timeout:
        pass
    ff.wait(timeout=30)
    return [p for p in out if relay_scan.rtp(p)]


def pcap(path, payloads):
    """A classic little-endian Ethernet pcap of UDP packets 10.0.0.1:5000 ->
    10.0.0.2:3478 carrying `payloads`."""
    with open(path, "wb") as f:
        f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
        for i, p in enumerate(payloads):
            udp = struct.pack(">HHHH", 5000, 3478, 8 + len(p), 0) + p
            ip = struct.pack(">BBHHHBBH4s4s", 0x45, 0, 20 + len(udp), 0, 0, 64, 17, 0,
                             bytes([10, 0, 0, 1]), bytes([10, 0, 0, 2])) + udp
            eth = b"\x00" * 12 + b"\x08\x00" + ip
            f.write(struct.pack("<IIII", 1000 + i // 50, (i % 50) * 20000, len(eth), len(eth)) + eth)


def header_len(p):
    n = 12 + 4 * (p[0] & 0x0F)
    if p[0] & 0x10:
        n += 4 + 4 * struct.unpack(">H", p[n + 2:n + 4])[0]
    return n


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    res = open(os.path.join(out_dir, "self_check.jsonl"), "a")
    ok = True
    with tempfile.TemporaryDirectory(dir=HERE) as tmp:
        track = os.path.join(tmp, "track.wav")
        call_track(track, relay_scan.CONTROL_CLICKS)
        _, peaks = coded(track, 0)
        pkts = capture(track)
        rng = random.Random(7)
        cases = {
            "plain": pkts,
            "channeldata": [struct.pack(">HH", 0x4000, len(p)) + p for p in pkts],
            "payload-random": [p[:header_len(p)] + bytes(rng.randrange(256) for _ in p[header_len(p):])
                               for p in pkts],
        }
        want = {"plain": list(range(9)), "channeldata": list(range(9)), "payload-random": []}
        for name, payloads in cases.items():
            path = os.path.join(tmp, f"{name}.pcap")
            pcap(path, payloads)
            found = []
            relay_scan.sound(path, peaks, found.append)
            codes = [c for r in found for c in r["codes"]]
            good = codes == [c % 6 for c in want[name]]
            ok &= good
            rec = {"case": name, "packets": len(payloads), "streams": len(found),
                   "codes": codes, "want": [c % 6 for c in want[name]], "ok": good}
            res.write(json.dumps(rec) + "\n")
            res.flush()
            print(json.dumps(rec), flush=True)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
