#!/usr/bin/env python3
"""Mutation test for the adversary harness (docs/GATE1.md).

Runs the toy system once correctly and once per deliberate defect. For each run:
the server container captures its own traffic with tcpdump while storing
messages in SQLite and logging headers; the client sends canary-bearing
messages, fetches them, keeps and purges a local history. Then canary_scan.py
scans everything an adversary could hold: server DB, server log, packet capture,
and the client's purged local DB.

Pass: the correct run is CLEAN (no false positives) and every defect is CAUGHT
in the artefact where it should appear. Results: results/<label>.jsonl, flushed.
Usage: mutation_test.py LABEL
"""
import json, os, secrets, shutil, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
IMG, SRV, CLI = "tremulator-toy:latest", "tadv-srv", "tadv-cli"
MODES = {  # defect: artefacts where it must appear (any one suffices)
    "none": [],
    "plaintext_body": ["traffic.pcap", "server.db"],
    "plaintext_attachment": ["traffic.pcap", "server.db"],
    "preview_leak": ["traffic.pcap", "server.db"],
    "purge_unlink_only": ["client.db"],
    "key_in_header": ["server.log", "traffic.pcap"],
    "base64_only": ["traffic.pcap", "server.db"],
    "gzip_only": ["traffic.pcap", "server.db"],
}
label = sys.argv[1]
os.makedirs(os.path.join(HERE, "results"), exist_ok=True)
res = open(os.path.join(HERE, "results", f"{label}.jsonl"), "a")
def log(r):
    r["t"] = time.strftime("%Y-%m-%dT%H:%M:%S"); res.write(json.dumps(r) + "\n"); res.flush(); print(json.dumps(r), flush=True)
def sh(cmd, timeout=180):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)

# One network and one container per role, created ONCE and reused across modes;
# each mode starts a fresh server process and capture inside the same container.
# The first version made a network and two containers per mode, and that
# interface churn raised "disconnected" desktop alerts on Grey's laptop
# (2026-09-21).
NET = "tadv-net"
outroot = os.path.join(HERE, "out", label)
os.makedirs(outroot, exist_ok=True)
def teardown():
    sh(["docker", "rm", "-f", SRV, CLI]); sh(["docker", "network", "rm", NET])
teardown()
sh(["docker", "network", "create", NET])
for c in (SRV, CLI):
    r = sh(["docker", "run", "-d", "--name", c, "--network", NET, "-v", f"{outroot}:/out", IMG, "sleep", "infinity"])
    if r.returncode: raise RuntimeError(r.stderr)
try:
    for mode, expect in MODES.items():
        base = os.path.join(outroot, mode); shutil.rmtree(base, ignore_errors=True)
        inp, srvd, clid = (os.path.join(base, d) for d in ("in", "srv", "cli"))
        for d in (inp, srvd, clid): os.makedirs(d)
        cb = f"/out/{mode}"
        key = secrets.token_hex(32)
        msgs = [f"m{i}\tCANARY-{secrets.token_hex(8)}" for i in range(5)]
        open(os.path.join(inp, "msgs.tsv"), "w").write("\n".join(msgs) + "\n")
        open(os.path.join(base, "canaries.tsv"), "w").write("\n".join(msgs + [f"key\t{key}"]) + "\n")
        sh(["docker", "exec", "-d", SRV, "sh", "-c",
            f"tcpdump -i eth0 -U -w {cb}/srv/traffic.pcap & sleep 1; "
            f"TOY_DB={cb}/srv/server.db TOY_LOG={cb}/srv/server.log exec python3 /toy/server.py"])
        time.sleep(3)
        r = sh(["docker", "exec", "-e", f"DEFECT={mode}", "-e", f"TOY_KEY_HEX={key}",
                "-e", f"TOY_LOCAL_DB={cb}/cli/client.db", CLI, "python3", "/toy/client.py", SRV, f"{cb}/in/msgs.tsv"])
        client_out = (r.stdout + r.stderr).strip()[-300:]
        time.sleep(1)
        sh(["docker", "exec", SRV, "sh", "-c", "pkill -INT tcpdump; pkill -f /toy/server.py; sleep 1"])
        hits_path = os.path.join(base, "hits.jsonl")
        sh(["python3", os.path.join(HERE, "canary_scan.py"), os.path.join(base, "canaries.tsv"), hits_path, srvd, clid])
        hits = [json.loads(l) for l in open(hits_path)] if os.path.exists(hits_path) else []
        where = sorted({os.path.basename(h["where"].split("#")[0].split("|")[0]) for h in hits})
        artefacts = sorted(os.listdir(srvd) + os.listdir(clid))
        ok = (not hits) if mode == "none" else any(a in where for a in expect)
        log({"run": label, "mode": mode, "client": client_out, "artefacts": artefacts,
             "hits": len(hits), "hit_in": where, "expected_in": expect,
             "verdict": "CLEAN" if not hits else "CAUGHT", "pass": ok})
finally:
    teardown()
res.close()
# Containers write as root; hand the outputs back to the invoking user.
sh(["docker", "run", "--rm", "-v", f"{os.path.join(HERE, 'out')}:/o", "tremulator-lab:latest",
    "chown", "-R", f"{os.getuid()}:{os.getgid()}", "/o"])
print("DONE", flush=True)
