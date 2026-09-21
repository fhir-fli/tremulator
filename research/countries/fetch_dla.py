#!/usr/bin/env python3
"""Fetch DLA Piper's Data Protection Laws of the World, one page per
jurisdiction, and split it into its sections.

Source: https://www.dlapiperdataprotection.com/index.html?t=law&c=<CODE>
Each page carries every section for that jurisdiction. Raw HTML is saved to
dla_raw/<CODE>.html; sections are appended to dla_sections.jsonl, one line per
jurisdiction, flushed after each. Resumable: jurisdictions already in the jsonl
are skipped.
"""
import html, json, os, re, subprocess, sys, time

SECTIONS = ["Law", "Definitions", "Authority", "Registration",
            "Data protection officers", "Collection and processing",
            "Transfer of personal data", "Security", "Breach notification",
            "Enforcement", "Electronic marketing", "Online privacy", "Key contacts"]
UA = "Mozilla/5.0 (X11; Linux x86_64) Chrome/120"

idx = open("dla.html", encoding="utf-8", errors="replace").read()
opts = [(c, " ".join(n.split())) for c, n in
        re.findall(r'<option[^>]*value="([A-Z0-9_-]+)"[^>]*>([^<]+)</option>', idx)]
opts = [o for o in opts if o[0]]
done = set()
if os.path.exists("dla_sections.jsonl"):
    for line in open("dla_sections.jsonl"):
        try: done.add(json.loads(line)["code"])
        except Exception: pass
print(f"jurisdictions: {len(opts)}; already done: {len(done)}", flush=True)

def to_lines(t):
    t = re.sub(r"<script.*?</script>|<style.*?</style>", " ", t, flags=re.S)
    t = re.sub(r"<[^>]+>", "\n", t)
    t = html.unescape(t)
    return [l.strip() for l in t.split("\n") if l.strip()]

out = open("dla_sections.jsonl", "a")
for i, (code, name) in enumerate(opts, 1):
    if code in done:
        continue
    url = f"https://www.dlapiperdataprotection.com/index.html?t=law&c={code}"
    raw = f"dla_raw/{code}.html"
    r = subprocess.run(["curl", "-sL", "-A", UA, "-o", raw, "-w", "%{http_code}", url],
                       capture_output=True, text=True, timeout=90)
    status = r.stdout.strip()
    body = open(raw, encoding="utf-8", errors="replace").read() if os.path.exists(raw) else ""
    lines = to_lines(body)
    mod = next((l for l in lines if l.startswith("Last modified")), "")
    # body starts after the table of contents; the first "Law" after "Table of contents"
    try:
        start = lines.index("Table of contents")
    except ValueError:
        start = 0
    heads = []
    j = start + 1 + len(SECTIONS)  # skip the TOC entries
    for s in SECTIONS:
        try:
            k = lines.index(s, j)
            heads.append((s, k)); j = k + 1
        except ValueError:
            heads.append((s, None))
    secs = {}
    found = [(s, k) for s, k in heads if k is not None]
    for n, (s, k) in enumerate(found):
        e = found[n + 1][1] if n + 1 < len(found) else len(lines)
        secs[s] = "\n".join(lines[k + 1:e])
    rec = {"code": code, "name": name, "http": status, "last_modified": mod,
           "sections_found": len(found), "sections": secs}
    out.write(json.dumps(rec, ensure_ascii=False) + "\n"); out.flush()
    print(f"{i:3}/{len(opts)} {code:6} {name[:34]:34} http={status} sections={len(found)} {mod}", flush=True)
    time.sleep(2)
out.close()
print("DONE", flush=True)
