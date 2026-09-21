#!/usr/bin/env python3
"""Toy client for the mutation test. Usage: client.py SERVER CANARIES_TSV
Sends every canary as a message body (and the first as an attachment), then
fetches, stores the history in its local SQLite, and purges it.

DEFECT (environment) selects one deliberate flaw; "none" is the correct
behaviour the scanner must NOT flag:
  none                 AES-GCM encrypts body and attachment with a key the server
                       never sees; local store encrypts each message under its own
                       key; purge destroys the keys with secure_delete on
  plaintext_body       body sent unencrypted
  plaintext_attachment attachment sent unencrypted, body encrypted
  preview_leak         encrypted body plus a plaintext "preview" for notifications
  purge_unlink_only    local history stored in plaintext; purge is a plain DELETE
  key_in_header        message key sent in a debug header the server logs
  base64_only          body base64-encoded but not encrypted
  gzip_only            body gzip-compressed and base64-encoded, not encrypted
"""
import base64, gzip, json, os, sqlite3, sys, urllib.request
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
SERVER, CFILE = sys.argv[1], sys.argv[2]
DEFECT = os.environ.get("DEFECT", "none")
LOCAL = os.environ.get("TOY_LOCAL_DB", "/work/client.db")
KEY = bytes.fromhex(os.environ["TOY_KEY_HEX"])   # shared by the two ends out of band
# Each canary is a short unique token; the message wraps it in clinical-looking
# filler so a truncated 40-character preview still contains the whole token.
canaries = [l.rstrip("\n").split("\t", 1)[1] + " | pt febrile 39.4, HIV PEP day 3"
            for l in open(CFILE) if l.strip()]

def enc(pt):
    n = os.urandom(12); return base64.b64encode(n + AESGCM(KEY).encrypt(n, pt.encode(), None)).decode()
def dec(ct):
    # Undo whatever this mode did to the body, so every mode reaches the local
    # history and purge step (the first version crashed here in the three
    # unencrypted modes).
    if DEFECT == "plaintext_body": return ct
    if DEFECT == "base64_only": return base64.b64decode(ct).decode()
    if DEFECT == "gzip_only": return gzip.decompress(base64.b64decode(ct)).decode()
    raw = base64.b64decode(ct); return AESGCM(KEY).decrypt(raw[:12], raw[12:], None).decode()

def post(obj, headers=None):
    req = urllib.request.Request(f"http://{SERVER}:8080/send", data=json.dumps(obj).encode(),
                                 headers={"Content-Type": "application/json", **(headers or {})})
    urllib.request.urlopen(req, timeout=10).read()

for i, c in enumerate(canaries):
    m = {"to": "bob", "n": i}
    if DEFECT == "plaintext_body": m["body"] = c
    elif DEFECT == "base64_only": m["body"] = base64.b64encode(c.encode()).decode()
    elif DEFECT == "gzip_only": m["body"] = base64.b64encode(gzip.compress(c.encode())).decode()
    else: m["body"] = enc(c)
    if i == 0:
        m["attachment"] = c if DEFECT == "plaintext_attachment" else enc(c)
    if DEFECT == "preview_leak": m["preview"] = c[:40]
    post(m, {"X-Debug-Key": KEY.hex()} if DEFECT == "key_in_header" else None)

rows = json.loads(urllib.request.urlopen(f"http://{SERVER}:8080/fetch/bob", timeout=10).read())
local = sqlite3.connect(LOCAL)
if DEFECT == "purge_unlink_only":
    # Debian (and this image) build SQLite with SECURE_DELETE on, so a plain
    # DELETE already zeroes freed pages there. The first mutation run showed it:
    # this defect came out clean because it never happened. Turn it off, as a
    # platform with the other default would, so the defect is real.
    local.execute("pragma secure_delete = off")
    local.execute("create table hist (id integer primary key, body text)")
    for r in rows:
        local.execute("insert into hist (body) values (?)", (dec(r["body"]),))
    local.commit()
    local.execute("delete from hist"); local.commit()          # unlink only: pages keep the bytes
else:
    local.execute("pragma secure_delete = on")
    local.execute("create table hist (id integer primary key, ct text, key_id integer)")
    local.execute("create table keys (id integer primary key, k blob)")
    for r in rows:
        mk = AESGCM.generate_key(bit_length=256); n = os.urandom(12)
        cur = local.execute("insert into keys (k) values (?)", (mk,))
        local.execute("insert into hist (ct, key_id) values (?, ?)",
                      (base64.b64encode(n + AESGCM(mk).encrypt(n, dec(r["body"]).encode(), None)).decode(), cur.lastrowid))
    local.commit()
    local.execute("delete from keys"); local.commit()          # crypto-erase: ciphertext left, keys gone
    local.execute("vacuum")
local.close()
print(json.dumps({"defect": DEFECT, "sent": len(canaries), "fetched": len(rows)}), flush=True)
