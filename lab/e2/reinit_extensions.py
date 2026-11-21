"""The extension types in each re_init_proposal of messages.json.
ReInit (RFC 9420 section 12.1.5): group_id<V>, uint16 version,
uint16 cipher_suite, Extension extensions<V>; Extension: uint16
extension_type, opaque extension_data<V>.

    python3 -I reinit_extensions.py MESSAGES_JSON
"""
import collections, json, sys

def vlen(b, at):
    size = 1 << (b[at] >> 6)
    n = b[at] & 0x3F
    for i in range(1, size):
        n = (n << 8) | b[at + i]
    return n, at + size

d = json.load(open(sys.argv[1]))
dup = 0
for i, e in enumerate(d):
    b = bytes.fromhex(e["re_init_proposal"])
    n, at = vlen(b, 0); at += n          # group_id
    at += 4                              # version, cipher_suite
    n, at = vlen(b, at); end = at + n
    types = []
    while at < end:
        t = int.from_bytes(b[at:at + 2], "big"); at += 2
        m, at = vlen(b, at); at += m
        types.append(t)
    assert at == end == len(b), i
    c = collections.Counter(types)
    d2 = {t: k for t, k in c.items() if k > 1}
    if d2:
        dup += 1
    print(i, "types", types, "duplicates", d2, flush=True)
print("entries", len(d), "with duplicate types", dup, flush=True)
