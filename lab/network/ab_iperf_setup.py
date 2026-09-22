#!/usr/bin/env python3
"""A/B: does link loss alone cause iperf3's UDP 'unable to read from stream
socket' error? Same containers, same persistent iperf3 server; only netem loss
changes. Appends one line per trial to results/ab_iperf_setup.jsonl."""
import json, signal, subprocess, sys, time
signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
NET, SRV, CLI, IMG = "tlab-ab", "tlab-ab-srv", "tlab-ab-cli", "tremulator-lab:latest"
def sh(c, t=60): return subprocess.run(c, capture_output=True, text=True, timeout=t)
out = open("results/ab_iperf_setup.jsonl", "a")
def cleanup():
    sh(["docker", "rm", "-f", SRV, CLI]); sh(["docker", "network", "rm", NET])
cleanup(); sh(["docker", "network", "create", NET])
try:
    for c in (SRV, CLI):
        sh(["docker", "run", "-d", "--rm", "--name", c, "--network", NET, "--cap-add", "NET_ADMIN", IMG])
    sh(["docker", "exec", SRV, "iperf3", "-s", "-D"]); time.sleep(1)
    for loss in (0, 30):
        for c in (SRV, CLI):
            sh(["docker", "exec", c, "tc", "qdisc", "replace", "dev", "eth0", "root", "netem", "delay", "50ms", "loss", f"{loss}%"])
        for i in range(40):
            r = sh(["docker", "exec", CLI, "iperf3", "-c", SRV, "-u", "-b", "200000", "-l", "200", "-t", "1", "-J"])
            try: j = json.loads(r.stdout); err = j.get("error", "")
            except ValueError: err = "no json: " + (r.stdout + r.stderr)[-120:]
            rec = {"loss_pct": loss, "trial": i, "setup_error": "stream socket" in err, "error": err[:120]}
            out.write(json.dumps(rec) + "\n"); out.flush()
        n = sum(1 for l in open("results/ab_iperf_setup.jsonl") if json.loads(l)["loss_pct"] == loss and json.loads(l)["setup_error"])
        print(f"loss {loss}%: setup errors {n}/40", flush=True)
finally:
    cleanup(); out.close()
