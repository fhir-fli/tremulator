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
def cleanup(net):
    sh(["docker", "rm", "-f", SRV, CLI]); sh(["docker", "network", "rm", net])

for mode, expect in MODES.items():
    base = os.path.join(HERE, "out", label, mode)
    shutil.rmtree(base, ignore_errors=True)
    inp, srvd, clid = (os.path.join(base, d) for d in ("in", "srv", "cli"))
    for d in (inp, srvd, clid): os.makedirs(d)
    key = secrets.token_hex(32)
    msgs = [f"m{i}\tCANARY-{secrets.token_hex(8)}" for i in range(5)]
    open(os.path.join(inp, "msgs.tsv"), "w").write("\n".join(msgs) + "\n")
    open(os.path.join(base, "canaries.tsv"), "w").write("\n".join(msgs + [f"key\t{key}"]) + "\n")
    net = f"tadv-{mode.replace('_', '-')}"
    cleanup(net); sh(["docker", "network", "create", net])
    try:
        r = sh(["docker", "run", "-d", "--name", SRV, "--network", net, "-v", f"{srvd}:/work",
                IMG, "sh", "-c", "tcpdump -i eth0 -U -w /work/traffic.pcap & sleep 1; exec python3 /toy/server.py"])
        if r.returncode: raise RuntimeError(r.stderr)
        time.sleep(3)
        r = sh(["docker", "run", "--rm", "--name", CLI, "--network", net, "-e", f"DEFECT={mode}",
                "-e", f"TOY_KEY_HEX={key}", "-v", f"{inp}:/in:ro", "-v", f"{clid}:/work",
                IMG, "python3", "/toy/client.py", SRV, "/in/msgs.tsv"])
        client_out = (r.stdout + r.stderr).strip()[-300:]
        time.sleep(1)
        sh(["docker", "exec", SRV, "sh", "-c", "pkill -INT tcpdump; sleep 1"])
    finally:
        sh(["docker", "stop", "-t", "2", SRV]); cleanup(net)
    hits_path = os.path.join(base, "hits.jsonl")
    s = sh(["python3", os.path.join(HERE, "canary_scan.py"), os.path.join(base, "canaries.tsv"),
            hits_path, srvd, clid])
    hits = [json.loads(l) for l in open(hits_path)] if os.path.exists(hits_path) else []
    where = sorted({os.path.basename(h["where"].split("#")[0].split("|")[0]) for h in hits})
    artefacts = sorted(os.listdir(srvd) + os.listdir(clid))
    ok = (not hits) if mode == "none" else any(a in where for a in expect)
    log({"run": label, "mode": mode, "client": client_out, "artefacts": artefacts,
         "hits": len(hits), "hit_in": where, "expected_in": expect,
         "verdict": "CLEAN" if not hits else "CAUGHT", "pass": ok})
res.close()
# Containers write as root; hand the outputs back to the invoking user.
sh(["docker", "run", "--rm", "-v", f"{os.path.join(HERE, 'out')}:/o", "tremulator-lab:latest",
    "chown", "-R", f"{os.getuid()}:{os.getgid()}", "/o"])
print("DONE", flush=True)
