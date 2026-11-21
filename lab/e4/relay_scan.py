#!/usr/bin/env python3
"""E4: what the relay could hear and see of a call (docs/GATE2-CALLS-PLAN.md).

    python3 lab/e4/relay_scan.py PROFILE_DIR OUT_JSONL

PROFILE_DIR is one profile's results from `calls.py --relay-capture`
(relay.pcap, relay_control.pcap, fingerprints.tsv, turn.log). One JSON line
per finding goes to OUT_JSONL, flushed; the last line is the summary.

Sound: every UDP payload the relay captured is unwrapped from the relay's
own framing (TURN ChannelData, RFC 8656 section 12.4: first two bits 01,
4-byte header; or a Send/Data indication, section 11, its DATA attribute
0x0013). RTP packets (RFC 3550: version 2; RTCP, RFC 5761 section 4,
second byte 192-223, skipped) are grouped by SSRC. Each stream is played,
as captured, to ffmpeg as Opus RTP (RFC 7587, 48 kHz) over loopback and
decoded; the clicks are looked for with the voice-delay detector
(lab/gate2/voice_delay.coded) against the click track itself. A stream
that is SRTP (RFC 3711) decodes to noise. The positive control is the same
scan of relay_control.pcap: the same track sent as plain Opus RTP.

Fingerprints: the phones' certificate fingerprints (fingerprints.tsv, as
the server hunt) hunted in relay.pcap and turn.log by canary_scan.py.

Certificates: DTLS handshake records in the clear (epoch 0; RFC 6347
section 4.1) are read for Certificate messages (type 11; fragments joined
by message_seq, section 4.2.3); each certificate's SHA-256 (RFC 8122
section 5) is compared with the fingerprints. ServerHello's version and
supported_versions (RFC 8446 section 4.2.1, 0xfefc for DTLS 1.3, RFC 9147
section 5.3) say which DTLS the call used.
"""
import collections
import hashlib
import json
import os
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GATE2 = os.path.join(HERE, "..", "gate2")
sys.path.insert(0, GATE2)
from media_pcap import packets  # noqa: E402
from voice_delay import call_track, coded  # noqa: E402

SCANNER = os.path.join(HERE, "..", "adversary", "canary_scan.py")
CONTROL_CLICKS = 9
MIN_PACKETS = 50


def unwrap(p):
    """The payload inside the relay's framing, or `p` itself."""
    if len(p) >= 4 and p[0] >> 6 == 1:  # ChannelData
        n = struct.unpack(">H", p[2:4])[0]
        return p[4:4 + n]
    if len(p) >= 20 and p[0] >> 6 == 0 and p[4:8] == b"\x21\x12\xa4\x42":
        kind = struct.unpack(">H", p[:2])[0]
        if kind in (0x0016, 0x0017):  # Send / Data indication
            at = 20
            while at + 4 <= len(p):
                t, n = struct.unpack(">HH", p[at:at + 4])
                if t == 0x0013:
                    return p[at + 4:at + 4 + n]
                at += 4 + ((n + 3) & ~3)
        return None  # other STUN: no media
    return p


def rtp(p):
    """(ssrc, payload type, sequence) of an RTP packet, or None."""
    if len(p) < 12 or p[0] >> 6 != 2 or 192 <= p[1] <= 223:
        return None
    seq, = struct.unpack(">H", p[2:4])
    ssrc, = struct.unpack(">I", p[8:12])
    return ssrc, p[1] & 0x7F, seq


def streams(pcap):
    by = collections.defaultdict(list)
    dtls = []
    for _, src, dst, payload in packets(pcap):
        p = unwrap(payload)
        if not p:
            continue
        if 20 <= p[0] <= 63:
            # Relayed, the 5-tuple is the relay's; the first bytes of the
            # ChannelData header (the channel) tell the two phones apart.
            dtls.append(((src, dst, payload[:2]), p))
            continue
        r = rtp(p)
        if r:
            by[(r[0], r[1])].append((r[2], p))
    return by, dtls


def decode(stream, pt, into):
    """The packets played to ffmpeg as Opus RTP; the WAV it wrote."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
    probe.close()
    sdp = os.path.join(into, "s.sdp")
    with open(sdp, "w") as f:
        f.write(f"v=0\no=- 0 0 IN IP4 127.0.0.1\ns=scan\nc=IN IP4 127.0.0.1\nt=0 0\n"
                f"m=audio {port} RTP/AVP {pt}\na=rtpmap:{pt} opus/48000/2\n")
    wav = os.path.join(into, "s.wav")
    ff = subprocess.Popen(["ffmpeg", "-y", "-loglevel", "error", "-protocol_whitelist",
                           "file,udp,rtp", "-reorder_queue_size", "0", "-i", sdp,
                           "-ac", "1", "-ar", "48000", "-c:a", "pcm_s16le", wav],
                          stdin=subprocess.DEVNULL, stderr=subprocess.PIPE)
    time.sleep(1.5)
    for _, p in stream:
        sock.sendto(p, ("127.0.0.1", port))
        time.sleep(0.002)
    time.sleep(2)
    ff.send_signal(signal.SIGINT)
    try:
        ff.wait(timeout=30)
    except subprocess.TimeoutExpired:
        ff.kill()
    return wav if os.path.exists(wav) and os.path.getsize(wav) > 44 else None


def sound(pcap, sent_peaks, out):
    """Beeps found per stream of `pcap`, each written to `out`."""
    by, dtls = streams(pcap)
    total = 0
    for (ssrc, pt), pkts in sorted(by.items()):
        if len(pkts) < MIN_PACKETS:
            continue
        with tempfile.TemporaryDirectory(dir=HERE) as tmp:
            wav = decode(pkts, pt, tmp)
            beeps = coded(wav, 0, sent_peaks)[0] if wav else []
        rec = {"pcap": os.path.basename(pcap), "ssrc": ssrc, "pt": pt,
               "packets": len(pkts), "decoded": wav is not None,
               "beeps": len(beeps), "codes": [c for _, c in beeps]}
        out(rec)
        total += len(beeps)
    return total, dtls


def certificates(dtls, out):
    """Certificate messages in clear handshake records; DTLS versions."""
    frags = collections.defaultdict(dict)
    lengths = {}
    versions = set()
    for flow, p in dtls:
        at = 0
        while at + 13 <= len(p):
            ctype = p[at]
            epoch, = struct.unpack(">H", p[at + 3:at + 5])
            n, = struct.unpack(">H", p[at + 11:at + 13])
            body = p[at + 13:at + 13 + n]
            at += 13 + n
            if ctype != 22 or epoch != 0:
                continue
            h = 0
            while h + 12 <= len(body):
                mtype = body[h]
                mlen = int.from_bytes(body[h + 1:h + 4], "big")
                mseq, = struct.unpack(">H", body[h + 4:h + 6])
                off = int.from_bytes(body[h + 6:h + 9], "big")
                flen = int.from_bytes(body[h + 9:h + 12], "big")
                frag = body[h + 12:h + 12 + flen]
                h += 12 + flen
                if mtype == 2 and off == 0:  # ServerHello
                    versions.add(frag[:2].hex())
                    if b"\x00\x2b\x00\x02\xfe\xfc" in frag:
                        versions.add("fefc (supported_versions)")
                if mtype == 11:
                    frags[(flow, mseq, mlen)][off] = frag
                    lengths[(flow, mseq, mlen)] = mlen
    found = []
    for key, parts in frags.items():
        whole = b"".join(parts[o] for o in sorted(parts))
        if len(whole) != lengths[key]:
            continue
        at = 3
        while at + 3 <= len(whole):
            n = int.from_bytes(whole[at:at + 3], "big")
            der = whole[at + 3:at + 3 + n]
            at += 3 + n
            fp = ":".join(f"{b:02X}" for b in hashlib.sha256(der).digest())
            if fp not in found:
                found.append(fp)
    out({"dtls_server_versions": sorted(versions), "certificates_in_clear": found})
    return found, sorted(versions)


def main():
    d, out_path = sys.argv[1:3]
    res = open(out_path, "a")

    def out(rec):
        res.write(json.dumps(rec) + "\n")
        res.flush()
        print(json.dumps(rec), flush=True)

    with tempfile.TemporaryDirectory(dir=HERE) as tmp:
        track = os.path.join(tmp, "track.wav")
        call_track(track, CONTROL_CLICKS)
        _, sent_peaks = coded(track, 0)
    control, _ = sound(os.path.join(d, "relay_control.pcap"), sent_peaks, out)
    call, dtls = sound(os.path.join(d, "relay.pcap"), sent_peaks, out)
    certs, versions = certificates(dtls, out)
    fps = [l.split("\t", 1)[1].strip() for l in open(os.path.join(d, "fingerprints.tsv")) if "\t" in l]
    hits = os.path.join(d, "relay_fingerprint_hits.jsonl")
    if os.path.exists(hits):
        os.remove(hits)
    scan = subprocess.run(["python3", "-I", SCANNER, os.path.join(d, "fingerprints.tsv"), hits,
                           os.path.join(d, "relay.pcap"), os.path.join(d, "turn.log")],
                          capture_output=True, text=True)
    nhits = sum(1 for _ in open(hits)) if os.path.exists(hits) else None
    out({"summary": True, "control_beeps": control, "control_clicks_sent": CONTROL_CLICKS,
         "call_beeps": call, "fingerprints": len(fps), "fingerprint_hits": nhits,
         "fingerprint_scan_exit": scan.returncode, "dtls_server_versions": versions,
         "certificates_in_clear": len(certs),
         "certificates_matching_fingerprints": sum(1 for c in certs if c in fps),
         "pass": control >= 0.9 * CONTROL_CLICKS and call == 0 and nhits == 0 and len(fps) > 0})


if __name__ == "__main__":
    main()
