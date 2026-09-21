#!/usr/bin/env python3
"""Extract Global Partners Digital's World Map of Encryption Laws and Policies,
one row per country, from the saved page gpd.html.

Source: https://www.gp-digital.org/world-map-of-encryption/ (fetched to gpd.html).
The page carries no "last updated" date; the newest law it cites is 2021, so
treat it as current to roughly 2021-2022. Writes one row per country and flushes.
"""
import csv, html, re, sys

CATS = ["General right to encryption",
        "Mandatory minimum or maximum encryption strength",
        "Licensing/registration requirements",
        "Import/export controls",
        "Other restrictions",
        "Obligations on individuals to assist authorities",
        "Obligations on providers to assist authorities"]
ASSESS = {"No information available", "Minimal restrictions", "Some restrictions",
          "Widespread restrictions"}

g = open("gpd.html", encoding="utf-8", errors="replace").read()
codes = dict(re.findall(r'<option value="([a-z]{2})">([^<]+)</option>', g))

def text(fragment):
    t = re.sub(r"<[^>]+>", "\n", fragment)
    t = html.unescape(t)
    return [l.strip() for l in t.split("\n") if l.strip()]

starts = [(m.start(), m.group(1)) for m in re.finditer(r'country-([a-z]{2})\b', g)]
# keep first occurrence per code
seen, blocks = set(), []
for pos, c in starts:
    if c in codes and c not in seen:
        seen.add(c); blocks.append((pos, c))
blocks.sort()

out = open("gpd_encryption.tsv", "w", newline="")
w = csv.writer(out, delimiter="\t")
w.writerow(["gpd_code", "country", "assessment"] + CATS)
out.flush()
n = 0
for i, (pos, c) in enumerate(blocks):
    end = blocks[i + 1][0] if i + 1 < len(blocks) else pos + 60000
    lines = text(g[pos:end])
    name = codes[c]
    # assessment: first line in ASSESS after the country name
    assessment = ""
    for l in lines[:12]:
        if l in ASSESS:
            assessment = l; break
    vals = []
    for cat in CATS:
        v = ""
        if cat in lines:
            j = lines.index(cat) + 1
            parts = []
            while j < len(lines) and lines[j] not in CATS and lines[j] not in (
                    "Assessment Text Area", "Active policy processes", "Law and policy",
                    "Read more", "Assessment"):
                parts.append(lines[j]); j += 1
            v = " ".join(parts)
        vals.append(v[:1500])
    w.writerow([c, name, assessment or "UNPARSED"] + vals)
    out.flush()
    n += 1
    print(f"{n:3} {c} {name[:30]:30} {assessment or 'UNPARSED'}", flush=True)
out.close()
print(f"rows written: {n}; selector countries: {len(codes)}", flush=True)
