#!/usr/bin/env python3
"""labkit.clear_shaping under a known condition: after it, no shaping and no
shaping loop may be left, and none may come back.

    python3 lab/gate2/shaping_check.py

One container (`g2c-shapecheck`, the phone image, default bridge network, no
network created) gets a netem delay, a P4 duty loop and a calls.py-style
link cut; clear_shaping runs; then for 40 s (longer than the duty loop's 30 s
up phase, so a surviving loop would re-apply netem) the qdisc and the loop
processes are read every 2 s. calls9 (2026-10-17) found the old clean-up
killed itself and cleared nothing. One line per reading in
results/shaping-check.jsonl, flushed. Do not start without Grey's go.
"""
import json
import os
import time

from labkit import LOOP_PIDS, clear_shaping, dx, netem, sh, start_duty_loop, start_loop

HERE = os.path.dirname(os.path.abspath(__file__))
NAME = "g2c-shapecheck"
PHONE_IMG = "tremulator-g2-calls:latest"


def main():
    out = open(os.path.join(HERE, "results", "shaping-check.jsonl"), "a")

    def log(rec):
        out.write(json.dumps(rec) + "\n")
        out.flush()
        print(json.dumps(rec), flush=True)

    sh(["docker", "rm", "-f", NAME])
    sh(["docker", "run", "-d", "--rm", "--name", NAME, "--cap-add", "NET_ADMIN", PHONE_IMG,
        "sleep", "infinity"], check=True)
    ok = True
    try:
        netem(NAME, 300, 125, 2)
        start_duty_loop((NAME,), 300, 250, 2)
        start_loop(NAME, "sleep 5; tc qdisc replace dev eth0 root netem loss 100%; sleep 60; "
                         "tc qdisc del dev eth0 root")
        time.sleep(1)
        before = dx(NAME, "cat", LOOP_PIDS, user="0").stdout.split()
        log({"step": "shaped", "loops": len(before),
             "qdisc": dx(NAME, "tc", "qdisc", "show", "dev", "eth0", user="0").stdout.strip()})
        if len(before) != 2:
            ok = False
        clear_shaping((NAME,))
        for i in range(20):
            q = dx(NAME, "tc", "qdisc", "show", "dev", "eth0", user="0").stdout.strip()
            alive = [p for p in before
                     if dx(NAME, "kill", "-0", p, user="0").returncode == 0]
            log({"step": "after-clear", "s": i * 2, "netem": "netem" in q, "loops_alive": alive})
            if "netem" in q or alive:
                ok = False
            time.sleep(2)
    finally:
        sh(["docker", "rm", "-f", NAME])
    log({"step": "verdict", "pass": ok})
    return ok


if __name__ == "__main__":
    raise SystemExit(0 if main() else 1)
