#!/usr/bin/env python3
"""First-pass classification of DLA Piper sections. PROVISIONAL: every row is
then read and corrected by hand in dla_reviewed.tsv. Keeps the triggering
sentence for every flag so the hand review can check it.

Flags:
  transfer_auto  LOCAL  data must stay in the country (localisation)
                 AUTH   transfers need the regulator's prior authorisation
                 FREE   no general restriction on transfers
                 COND   allowed on conditions (adequacy, consent, contract ...)
                 NONE   section empty
  vital_auto     yes if a derogation for the data subject's life / vital
                 interests is mentioned in the transfer section
  health_sensitive_auto  yes if "health" appears in the definition of
                 sensitive / special data
  medical_basis_auto     yes if processing sensitive data for medical care by a
                 health professional is mentioned in collection/processing
"""
import csv, json, re

def sentences(t):
    # DLA's pages break lines at every quotation mark, so a newline is not a
    # sentence boundary. Flatten first, then split on sentence-ending full stops.
    # (First version split on newlines and missed "special categories ... health"
    # in every GDPR country: 29/164 instead of all EU members. Fixed 2026-09-21.)
    flat = " ".join(t.split())
    flat = re.sub(r'\s+([",”“])\s*', r'\1 ', flat)
    return [s.strip() for s in re.split(r"(?<=[.])\s+(?=[A-Z“\"(])", flat) if s.strip()]

def first(pats, text):
    for s in sentences(text):
        for p in pats:
            if re.search(p, s, re.I):
                return s[:300]
    return ""

LOCAL = [r"\blocali[sz]ation\b", r"\b(must|shall|required to) be (stored|kept|processed|hosted|retained|located)\b[^.]{0,80}\b(in|within)\b",
         r"\bwithin the territory\b", r"\blocal copy\b", r"\bstored (locally|in (the )?country)\b",
         r"\bprohibit\w*\b[^.]{0,60}\btransfer\w*\b[^.]{0,60}\b(outside|abroad)\b"]
AUTH  = [r"\b(prior )?(authori[sz]ation|approval|permission) (of|from) the\b[^.]{0,60}\b(authority|commission|agency|regulator|office|ministry|bank)\b",
         r"\bprior (authori[sz]ation|approval)\b"]
FREE  = [r"\bdoes not (specifically )?regulate\b[^.]{0,40}\btransfer", r"\bno (general |specific )?restrictions? on\b[^.]{0,30}\btransfer",
         r"\bno (specific )?(data protection )?(law|legislation)\b[^.]{0,60}\btransfer", r"\bthere are no\b[^.]{0,40}\btransfer"]
VITAL = [r"\bvital interests?\b", r"\blife of the data subject\b", r"\bprotect\w* (the )?life\b", r"\blife or (physical )?(safety|integrity|health)\b",
         r"\bpreserv\w* the life\b", r"\blife, (health|physical)\b"]
HEALTH_DEF = [r"\b(sensitive|special)\b[^.]{0,400}\bhealth\b", r"\bhealth\b[^.]{0,200}\b(sensitive|special)\b"]
MEDICAL = [r"\bmedical\b[^.]{0,200}\b(professional|practitioner|diagnos\w*|treatment|health ?care)\b",
           r"\bhealth ?care\b[^.]{0,120}\b(professional|provider|practitioner)\b[^.]{0,200}\b(secrecy|confidential\w*)\b",
           r"\bpreventive or occupational medicine\b"]

out = open("dla_auto.tsv", "w", newline="")
w = csv.writer(out, delimiter="\t")
w.writerow(["code","name","last_modified","transfer_auto","transfer_evidence",
            "vital_auto","vital_evidence","health_sensitive_auto","health_evidence",
            "medical_basis_auto","medical_evidence","law_first_line"])
out.flush()
for line in open("dla_sections.jsonl"):
    r = json.loads(line); s = r["sections"]
    tr = s.get("Transfer of personal data", "")
    body = "\n".join(tr.split("\n")[1:])  # drop the heading line
    ev_l, ev_a, ev_f = first(LOCAL, body), first(AUTH, body), first(FREE, body)
    if not body.strip(): cls, ev = "NONE", ""
    elif ev_l: cls, ev = "LOCAL", ev_l
    elif ev_a: cls, ev = "AUTH", ev_a
    elif ev_f: cls, ev = "FREE", ev_f
    else: cls, ev = "COND", sentences(body)[0][:300] if sentences(body) else ""
    vit = first(VITAL, body)
    hd = first(HEALTH_DEF, s.get("Definitions", ""))
    md = first(MEDICAL, s.get("Collection and processing", "") + "\n" + s.get("Definitions", ""))
    law = sentences("\n".join(s.get("Law","").split("\n")[1:]))
    w.writerow([r["code"], r["name"], r["last_modified"].replace("Last modified ",""), cls, ev,
                "yes" if vit else "no", vit, "yes" if hd else "no", hd, "yes" if md else "no", md,
                law[0][:300] if law else ""])
    out.flush()
out.close()
import collections
rows = list(csv.DictReader(open("dla_auto.tsv"), delimiter="\t"))
print("rows", len(rows), flush=True)
for col in ["transfer_auto","vital_auto","health_sensitive_auto","medical_basis_auto"]:
    print(col, dict(collections.Counter(r[col] for r in rows)), flush=True)
