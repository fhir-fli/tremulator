#!/usr/bin/env python3
"""Known-positive and known-negative checks for canary_scan.py, one per encoding.
A scanner that never fires is broken; so is one that fires on clean data."""
import base64, gzip, json, os, subprocess, sys, tempfile, zlib, urllib.parse
here = os.path.dirname(os.path.abspath(__file__))
C = "CANARY-7f3a9c2e41b0d6f8 pt febrile HIV PEP day 3"
cases = {
    "utf8": C.encode(), "utf16le": C.encode("utf-16-le"), "hex": C.encode().hex().encode(),
    "url": urllib.parse.quote(C).encode(), "json_u": json.dumps(C, ensure_ascii=True).encode().replace(b"C", b"\\u0043"),
    "b64_aligned": base64.b64encode(C.encode()), "b64_offset1": base64.b64encode(b"x" + C.encode()),
    "b64_offset2": base64.b64encode(b"xy" + C.encode()), "gzip": gzip.compress(b"{\"m\":\"" + C.encode() + b"\"}"),
    "zlib": zlib.compress(b"prefix " + C.encode()), "b64_of_gzip": base64.b64encode(gzip.compress(C.encode())),
}
negatives = {"random": os.urandom(4096), "near_miss": C.replace("7f3a", "7f3b").encode()}
fails = 0
with tempfile.TemporaryDirectory() as d:
    cf = os.path.join(d, "c.tsv"); open(cf, "w").write("c1\t" + C + "\n")
    for name, blob in {**cases, **negatives}.items():
        p = os.path.join(d, name + ".bin"); open(p, "wb").write(b"junk" + blob + b"junk")
        r = subprocess.run([sys.executable, os.path.join(here, "canary_scan.py"), cf, os.path.join(d, "h.jsonl"), p],
                           capture_output=True, text=True)
        found = r.returncode == 1; want = name in cases
        ok = found == want; fails += not ok
        print(f"{'ok  ' if ok else 'FAIL'} {name:12} want_found={want} found={found}", flush=True)
print(f"{len(cases)+len(negatives)-fails}/{len(cases)+len(negatives)} pass", flush=True)
sys.exit(1 if fails else 0)
