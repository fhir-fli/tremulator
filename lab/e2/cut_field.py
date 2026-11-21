"""A copy of the vector files with one messages.json field of entry 0 cut by
one byte, to see the added field check (patches/messages-three-fields.py)
go red.

    python3 -I lab/e2/cut_field.py OFFICIAL_DIR OUT_DIR FIELD
"""
import json, os, shutil, sys

src, out, field = sys.argv[1:4]
os.makedirs(out, exist_ok=True)
for name in os.listdir(src):
    if name.endswith(".json"):
        shutil.copy(os.path.join(src, name), os.path.join(out, name))
p = os.path.join(out, "messages.json")
d = json.load(open(p))
d[0][field] = d[0][field][:-2]
json.dump(d, open(p, "w"))
print(field, "entry 0 cut by one byte", flush=True)
