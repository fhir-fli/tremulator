"""The RTP packets in a phone's <phone>_media.pcap (calls.media_capture):
for each, the capture time and the clear part of its header. SRTP leaves
the 12-byte RTP header unencrypted (RFC 3711 section 3.1), so sequence
numbers and timestamps read straight off the wire. Relayed packets come
inside TURN ChannelData (RFC 8656 section 12.4: a 4-byte header whose
first two bits are 01), which is stripped. RTCP (RFC 5761 section 4:
packet types 192-223 in the second byte), STUN (first byte 0-3) and DTLS
(20-63, RFC 7983) are skipped.

usage: python3 media_pcap.py <phone>_media.pcap   (prints a count per stream)"""
import collections
import struct
import sys


def packets(path):
    """(time, src "ip:port", dst "ip:port", payload) for every UDP/IPv4
    packet on Ethernet in a classic pcap."""
    with open(path, "rb") as f:
        head = f.read(24)
        magic = struct.unpack("<I", head[:4])[0]
        if magic == 0xA1B2C3D4:
            end, scale = "<", 1e-6
        elif magic == 0xA1B23C4D:
            end, scale = "<", 1e-9
        else:
            raise RuntimeError(f"{path}: not a little-endian pcap (magic {magic:#x})")
        if struct.unpack(end + "I", head[20:24])[0] != 1:
            raise RuntimeError(f"{path}: link type is not Ethernet")
        while True:
            rec = f.read(16)
            if len(rec) < 16:
                return
            sec, frac, incl, _orig = struct.unpack(end + "IIII", rec)
            data = f.read(incl)
            if len(data) < 14 + 20 + 8 or data[12:14] != b"\x08\x00":
                continue
            ip = data[14:]
            ihl = (ip[0] & 0x0F) * 4
            if ip[9] != 17:
                continue
            src = ".".join(str(b) for b in ip[12:16])
            dst = ".".join(str(b) for b in ip[16:20])
            sport, dport = struct.unpack(">HH", ip[ihl:ihl + 4])
            yield sec + frac * scale, f"{src}:{sport}", f"{dst}:{dport}", ip[ihl + 8:]


def rtp(path):
    """(time, src, dst, ssrc, seq, timestamp, payload type, marker, relayed)
    for every RTP packet in the capture, in capture order."""
    for t, src, dst, p in packets(path):
        relayed = False
        if len(p) >= 4 and 0x40 <= p[0] < 0x80:
            p, relayed = p[4:], True
        if len(p) < 12 or not 0x80 <= p[0] < 0xC0 or 192 <= p[1] <= 223:
            continue
        seq, ts, ssrc = struct.unpack(">HII", p[2:12])
        yield t, src, dst, ssrc, seq, ts, p[1] & 0x7F, p[1] >> 7, relayed


if __name__ == "__main__":
    n = collections.Counter()
    for t, src, dst, ssrc, seq, ts, pt, m, relayed in rtp(sys.argv[1]):
        n[(src, dst, ssrc, pt, relayed)] += 1
    for k, v in sorted(n.items(), key=lambda kv: -kv[1]):
        print(v, *k, flush=True)
