"""What the Gate 2 lab runs share: shell and docker exec helpers, the network
profiles of docs/SUCCESS.md and their tc shaping, and a fresh fhirant per
profile. run.py (text) and calls.py (calls) both import it; nothing here
runs on import.

Every pkill here runs INSIDE a container through docker exec, never on the
host.
"""
import os
import json
import subprocess
import sys
import time
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FHIRANT = os.path.abspath(os.path.join(REPO, "..", "fhirant"))
SRV_IMG = "tremulator-g2-server:latest"

PROFILES = {  # name: (rate_kbit, rtt_ms, loss_pct, internal_network)
    "P1": (50, 400, 5, False),
    "P2": (300, 200, 2, False),
    "P3": (1000, 700, 1, False),
    "P4": (300, 250, 2, False),
    "P5": (10000, 5, 0, True),
}
# Each shaping loop (P4's duty cycle, calls.py's link cuts) writes its shell's
# pid here, inside its container, and clear_shaping kills by it. Until
# 2026-10-17 the loops carried a tag and clear_shaping killed by matching the
# tag in command lines, from an `sh -c` whose own command line held the tag:
# it killed itself (exit 143, reproduced in g2c-turn) before `tc qdisc del`
# ran, so neither the loops nor any shaping were cleared between profiles.
LOOP_PIDS = "/tmp/shaping-loop.pids"


def sh(cmd, timeout=600, check=False, **kw):
    """Runs cmd. A command still running at `timeout` counts as failed with
    exit 124, as timeout(1) reports it, unless `check` is set, which raises.
    calls13 offercut60-blocked: one `docker exec ... test -e` poll took over
    10 s (Alice's container stalled ~13 s, her stats lines show the gap;
    cause unknown) and the uncaught TimeoutExpired ended the whole sweep."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)
    except subprocess.TimeoutExpired as e:
        if check:
            raise RuntimeError(f"{' '.join(cmd)}: timed out after {timeout} s") from e
        out = e.stdout.decode() if isinstance(e.stdout, bytes) else (e.stdout or "")
        print(json.dumps({"event": "command-timed-out", "cmd": cmd, "timeout_s": timeout}), flush=True)
        return subprocess.CompletedProcess(cmd, 124, out, f"timed out after {timeout} s")
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}: {r.stderr.strip()}")
    return r


def dx(c, *args, timeout=600, user=None):
    u = ["-u", user] if user else []
    return sh(["docker", "exec", *u, c, *args], timeout=timeout)


def ip_of(c):
    return dx(c, "sh", "-c", "ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1").stdout.strip()


def pin_neighbours(cs):
    """As validate.py: permanent ARP entries, so a P4 outage only drops packets."""
    info = {c: (ip_of(c), dx(c, "cat", "/sys/class/net/eth0/address").stdout.strip()) for c in cs}
    for a in cs:
        for b in cs:
            if a != b:
                dx(a, "ip", "neigh", "replace", info[b][0], "lladdr", info[b][1],
                   "dev", "eth0", "nud", "permanent")


def netem(c, rate, delay_ms, loss):
    args = ["tc", "qdisc", "replace", "dev", "eth0", "root", "netem",
            "delay", f"{delay_ms}ms", "loss", f"{loss}%"]
    if rate:
        args += ["rate", f"{rate}kbit"]
    # As root: the calls image runs as `ubuntu`, and NET_ADMIN reaches only
    # root inside the container (calls6: "Operation not permitted").
    r = dx(c, *args, user="0")
    if r.returncode:
        raise RuntimeError(f"netem on {c}: {r.stderr.strip()}")


def clear_shaping(cs):
    """Kills every shaping loop by its recorded pid, removes the shaping, and
    proves it: no netem left on any interface and no loop pid on record."""
    for c in cs:
        dx(c, "sh", "-c", f"[ -f {LOOP_PIDS} ] && kill $(cat {LOOP_PIDS}) 2>/dev/null; "
                          f"rm -f {LOOP_PIDS}; tc qdisc del dev eth0 root 2>/dev/null; true", user="0")
    for c in cs:
        left = dx(c, "tc", "qdisc", "show", "dev", "eth0", user="0").stdout
        loops = dx(c, "sh", "-c", f"cat {LOOP_PIDS} 2>/dev/null; true", user="0").stdout.strip()
        if "netem" in left or loops:
            raise RuntimeError(f"shaping not cleared on {c}: {left.strip()} loops={loops!r}")


def start_loop(c, body):
    """Runs shell `body` in container c as root, its pid recorded for
    clear_shaping."""
    sh(["docker", "exec", "-d", "-u", "0", c, "sh", "-c", f"echo $$ >> {LOOP_PIDS}; {body}"])


PORTS = {"P1": 8081, "P2": 8082, "P3": 8083, "P4": 8084, "P5": 8085, "P0": 8080,
         "none": 8086, "plus500": 8087, "cut20": 8088, "cut60": 8089, "cut120": 8090,
         "offercut60": 8091, "answercut60": 8092}


def start_server(srv, profile, port=None):
    """A fresh fhirant on its own port, pid recorded for the stop. run3's
    stop (pkill by name) never killed P1's server, so P2 ran on P1's store
    and Bob's wiped keys no longer matched his old key packages there.
    `port` defaults to the profile's own; calls.py passes the base profile's
    for its variants (P2-blocked runs on P2's port, after P2's server is
    proved stopped)."""
    d = f"/out/{profile}"
    port = port or PORTS[profile]
    dx(srv, "mkdir", "-p", d, user="0")
    dx(srv, "chown", "-R", "1000:1000", "/out", user="0")
    dx(srv, "sh", "-c", f"rm -rf /data/{profile}; mkdir -p /data/{profile}")
    if dx(srv, "curl", "-fsS", f"http://127.0.0.1:{port}/health", timeout=10).returncode == 0:
        raise RuntimeError(f"port {port} already answers: a server is still running")
    sh(["docker", "exec", "-d", "-u", "0", srv, "sh", "-c",
        f"tcpdump -i eth0 -w {d}/traffic.pcap -U 2>{d}/tcpdump.err & echo $! > {d}/tcpdump.pid"])
    sh(["docker", "exec", "-d", srv, "sh", "-c",
        f"/app/bin/server --dev-mode --port {port} --db-path /data/{profile} "
        f"--spec-path /data/empty-spec > {d}/server.log 2>&1 & echo $! > {d}/server.pid"])
    for _ in range(60):
        if dx(srv, "curl", "-fsS", f"http://127.0.0.1:{port}/health", timeout=10).returncode == 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError("fhirant did not come up")
    devices = dx(srv, "sh", "-c",
                 f"curl -s 'http://127.0.0.1:{port}/Device?_summary=count&_format=json'", timeout=20).stdout
    if '"total":0' not in devices.replace(" ", ""):
        raise RuntimeError(f"store not fresh at start: {devices[:200]}")
    return port


def stop_server(srv, profile, port=None):
    d = f"/out/{profile}"
    port = port or PORTS[profile]
    # the server's own view of every blob, then the raw store file
    # Each step's exit and errors go to this run's output: calls241fc P1,
    # the dumps never reached the server and it was still answering 20 s
    # after the kill, and nothing recorded why.
    def step(what, *args, **kw):
        r = dx(srv, *args, **kw)
        print(json.dumps({"stop_server": what, "profile": profile, "exit": r.returncode,
                          "stdout": r.stdout[-2000:], "stderr": r.stderr[-500:]}), file=sys.stderr, flush=True)
    step("dump", "sh", "-c",
         f"curl -s 'http://127.0.0.1:{port}/Communication?_count=1000&_format=json' > {d}/server_dump.json")
    step("devices", "sh", "-c",
         f"curl -s 'http://127.0.0.1:{port}/Device?_count=1000&_format=json' > {d}/devices_dump.json")
    step("kill", "sh", "-c", f"kill -INT $(cat {d}/server.pid); sleep 2; kill -KILL $(cat {d}/server.pid) 2>/dev/null; true", user="0")
    step("tcpdump", "sh", "-c", f"kill -INT $(cat {d}/tcpdump.pid); sleep 1; true", user="0")
    for _ in range(20):
        if dx(srv, "curl", "-fsS", f"http://127.0.0.1:{port}/health", timeout=10).returncode != 0:
            break
        time.sleep(1)
    else:
        step("ps", "ps", "-ef")
        step("pid file", "cat", f"{d}/server.pid")
        raise RuntimeError(f"server on {port} did not stop")
    dx(srv, "sh", "-c", f"cp /data/{profile}/fhirant.db {d}/fhirant.db", user="0")
    dx(srv, "chown", "-R", f"{os.getuid()}:{os.getgid()}", "/out", user="0")


def start_duty_loop(cs, rate, rtt, loss):
    """P4: 30 s of link, then 60 s of nothing, over and over, on every
    container; killed by clear_shaping by its recorded pid."""
    loop = ("while true; do "
            f"tc qdisc replace dev eth0 root netem delay {rtt/2}ms loss {loss}% rate {rate}kbit; "
            f"sleep 30; tc qdisc replace dev eth0 root netem loss 100%; sleep 60; done")
    for c in cs:
        start_loop(c, loop)


def build_server():
    sh(["docker", "build", "-t", "fhirant:latest", FHIRANT], check=True, timeout=3600)
    sh(["docker", "build", "-t", SRV_IMG, "-f", os.path.join(HERE, "Dockerfile.server"), HERE],
       check=True, timeout=1200)


def utc(text):
    """An ISO time with up to nanoseconds, as a float of seconds."""
    text = text.strip().replace("Z", "")
    head, _, frac = text.partition(".")
    return datetime.fromisoformat(head + "+00:00").timestamp() + float("0." + (frac or "0"))


def freeze_spans(log_text, length):
    """(start, end) spans from ffmpeg freezedetect output. A span still open
    when the recording ends runs to its end: freezedetect prints no duration
    for it (calls1 read a fully frozen recording as 0 freezes)."""
    spans, start = [], None
    for line in log_text.splitlines():
        if "freeze_start:" in line:
            start = float(line.split("freeze_start:")[1])
        elif "freeze_end:" in line and start is not None:
            spans.append((start, float(line.split("freeze_end:")[1])))
            start = None
    if start is not None:
        spans.append((start, length))
    return spans
