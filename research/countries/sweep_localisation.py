#!/usr/bin/env python3
"""NOTE 2026-09-21: DLA itself omits some storage rules. Kenya's LN 263/2021
reg 26(2)(f) (health care data in Kenya) is absent from DLA's Kenya page and was
added by hand from Kenya Law. Counts built on this sweep are a floor.

Sweep EVERY section of every DLA jurisdiction for data-localisation language,
not only the transfer section. Writes one line per hit to localisation_hits.tsv,
flushed, for hand review."""
import csv, json, re
PAT = re.compile(r"(locali[sz]\w*|(stored?|kept|processed|hosted|located|retained|record\w*)\b[^.]{0,40}\b(with)?in (the )?(territory|country|republic|kingdom|federation|jurisdiction)\b"
                 r"|(server|data ?cent(re|er)|database)s?\b[^.]{0,40}\blocated\b[^.]{0,30}\b(in|within)\b"
                 r"|within the territory\b|local copy|on (the )?territory of)", re.I)
out = open("localisation_hits.tsv", "w", newline="")
w = csv.writer(out, delimiter="\t"); w.writerow(["code","name","section","context"]); out.flush()
n = 0; per = {}
for line in open("dla_sections.jsonl"):
    r = json.loads(line)
    # Also match the jurisdiction's own name ("must store personal data in
    # Rwanda"). The first version matched only generic words and missed Rwanda's
    # Art 50, which a known-positive probe caught (2026-09-21).
    nm = re.escape(r["name"].split(" - ")[0].replace("the ", ""))
    own = re.compile(r"(stor\w*|kept|process\w*|host\w*|server\w*|data ?cent\w*)\b[^.]{0,50}\b(in|within|inside)\s+(the\s+)?" + nm + r"\b", re.I)
    for sec, txt in r["sections"].items():
        # Drop the heading line ("Collection and processing in Kenya"), which
        # the own-name pattern otherwise matches in every jurisdiction.
        flat = " ".join("\n".join(txt.split("\n")[1:]).split())
        seen_spans = set()
        for m in list(PAT.finditer(flat)) + list(own.finditer(flat)):
            if any(abs(m.start() - s0) < 120 for s0 in seen_spans):
                continue
            seen_spans.add(m.start())
            ctx = flat[max(0, m.start()-220): m.end()+220]
            w.writerow([r["code"], r["name"], sec, ctx]); out.flush()
            n += 1; per[r["code"]] = per.get(r["code"], 0) + 1
out.close()
print(f"hits {n} across {len(per)} jurisdictions", flush=True)
print(sorted(per.items(), key=lambda x: -x[1]), flush=True)
