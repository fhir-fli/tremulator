#!/usr/bin/env python3
"""Scan files and packet captures for planted canary strings.

Usage: canary_scan.py CANARIES_FILE OUT_JSONL PATH [PATH ...]
CANARIES_FILE: one canary per line, "id<TAB>text".
A PATH may be a file or a directory (walked). Files ending .pcap are also parsed:
TCP streams are reassembled per direction and UDP payloads extracted, and those
are scanned in addition to the raw file bytes.

Each canary is searched in these forms: UTF-8, UTF-16LE, UTF-16BE, hex (both
cases), URL-encoded, JSON \\u-escaped, and base64 at all three alignments. Any
gzip or zlib stream found in a blob is decompressed and the result scanned too,
and base64 runs are decoded and rescanned (two levels), as are JSON string literals
containing \\u escapes. Every hit is written to
OUT_JSONL and flushed. Exit status 1 if anything was found, 0 if clean.
"""
import base64, binascii, json, os, re, struct, sys, urllib.parse, zlib

def variants(text):
    b = text.encode("utf-8")
    v = {"utf8": b, "utf16le": text.encode("utf-16-le"), "utf16be": text.encode("utf-16-be"),
         "hex": binascii.hexlify(b), "HEX": binascii.hexlify(b).upper(),
         "url": urllib.parse.quote(text).encode(), "json_u": "".join(f"\\u{ord(c):04x}" for c in text).encode()}
    for pad in range(3):   # base64 of the canary at each alignment; keep the stable middle
        enc = base64.b64encode(b"\0" * pad + b)
        skip = (pad * 4 + 2) // 3 + (1 if pad else 0)
        core = enc[skip: len(enc) - 4]
        if len(core) >= 8: v[f"b64_{pad}"] = core
    return v

def decoded_children(blob):
    """Yield (how, bytes) for compressed streams and base64 runs inside blob."""
    for m in re.finditer(rb"\x1f\x8b\x08", blob):
        try:
            d = zlib.decompressobj(16 + zlib.MAX_WBITS); yield ("gzip", d.decompress(blob[m.start():]))
        except zlib.error: pass
    for m in re.finditer(rb"\x78[\x01\x5e\x9c\xda]", blob):
        try:
            d = zlib.decompressobj(); out = d.decompress(blob[m.start():])
            if out: yield ("zlib", out)
        except zlib.error: pass
    # JSON string literals containing \u escapes: encoders escape only some
    # characters, so decode the literal instead of matching one escaped form.
    for m in re.finditer(rb'"(?:[^"\\]|\\.){0,4096}?\\u[0-9a-fA-F]{4}(?:[^"\\]|\\.){0,4096}"', blob):
        try: yield ("json", json.loads(m.group(0).decode("latin-1")).encode("utf-8", "surrogatepass"))
        except (ValueError, UnicodeError): pass
    for m in re.finditer(rb"[A-Za-z0-9+/]{16,}={0,2}", blob):
        s = m.group(0)
        s = s[: len(s) - len(s) % 4] if not s.endswith(b"=") else s
        try: yield ("base64", base64.b64decode(s, validate=True))
        except (binascii.Error, ValueError): pass

def scan_blob(blob, canaries, where, emit, depth=0):
    for cid, forms in canaries.items():
        for form, needle in forms.items():
            i = blob.find(needle)
            if i >= 0:
                emit({"where": where, "canary": cid, "form": form, "offset": i})
    # Two levels: base64 wrapping gzip is a common way plaintext hides.
    if depth < 2:
        for how, child in decoded_children(blob):
            scan_blob(child, canaries, f"{where}|{how}", emit, depth + 1)

def pcap_streams(data):
    """Classic libpcap: return {flow: bytes} for TCP (reassembled) and a list of UDP payloads."""
    if len(data) < 24: return {}, []
    magic = data[:4]
    endian = "<" if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
    linktype = struct.unpack(endian + "I", data[20:24])[0]
    off, segs, udp = 24, {}, []
    while off + 16 <= len(data):
        _, _, incl, _ = struct.unpack(endian + "IIII", data[off:off+16]); off += 16
        pkt = data[off:off+incl]; off += incl
        if linktype == 1:  eth, l3 = pkt[12:14], pkt[14:]            # Ethernet
        elif linktype == 113: eth, l3 = pkt[14:16], pkt[16:]         # Linux cooked
        elif linktype == 276: eth, l3 = pkt[0:2], pkt[20:]           # Linux cooked v2
        else: continue
        if eth == b"\x08\x00" and len(l3) >= 20:
            ihl = (l3[0] & 15) * 4; proto = l3[9]; src, dst = l3[12:16], l3[16:20]; l4 = l3[ihl:]
        elif eth == b"\x86\xdd" and len(l3) >= 40:
            proto = l3[6]; src, dst = l3[8:24], l3[24:40]; l4 = l3[40:]
        else: continue
        if proto == 6 and len(l4) >= 20:
            sp, dp, seq = struct.unpack("!HHI", l4[:8]); doff = (l4[12] >> 4) * 4; payload = l4[doff:]
            if payload: segs.setdefault((src, sp, dst, dp), {})[seq] = payload
        elif proto == 17 and len(l4) >= 8:
            udp.append(l4[8:])
    streams = {}
    for flow, d in segs.items():
        streams[flow] = b"".join(d[s] for s in sorted(d))   # retransmissions share a seq and collapse
    return streams, udp

def main():
    cfile, outp, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
    canaries = {}
    for line in open(cfile, encoding="utf-8"):
        if line.strip():
            cid, text = line.rstrip("\n").split("\t", 1); canaries[cid] = variants(text)
    out = open(outp, "w"); hits = []
    def emit(h):
        hits.append(h); out.write(json.dumps(h) + "\n"); out.flush()
    files = []
    for p in paths:
        if os.path.isdir(p):
            for root, _, names in os.walk(p):
                files += [os.path.join(root, n) for n in names]
        elif os.path.exists(p): files.append(p)
    for f in sorted(files):
        data = open(f, "rb").read()
        scan_blob(data, canaries, f, emit)
        if f.endswith(".pcap"):
            streams, udp = pcap_streams(data)
            for flow, s in streams.items():
                scan_blob(s, canaries, f"{f}#tcp", emit)
            for i, u in enumerate(udp):
                scan_blob(u, canaries, f"{f}#udp{i}", emit)
    out.close()
    print(json.dumps({"files": len(files), "hits": len(hits)}), flush=True)
    sys.exit(1 if hits else 0)

if __name__ == "__main__":
    main()
