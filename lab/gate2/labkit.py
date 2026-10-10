"""What the Gate 2 lab runs share: shell and docker exec helpers, the network
profiles of docs/SUCCESS.md and their tc shaping, and a fresh fhirant per
profile. run.py (text) and calls.py (calls) both import it; nothing here
runs on import.

Every pkill here runs INSIDE a container through docker exec, never on the
host.
"""
import os
import subprocess
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
DUTY_LOOP_MARK = "tremulator-duty-loop"  # a tag the loop carries, for its kill


def sh(cmd, timeout=600, check=False, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)
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
    r = dx(c, *args)
    if r.returncode:
        raise RuntimeError(f"netem on {c}: {r.stderr.strip()}")


def clear_shaping(cs):
    # The duty loop is killed by the tag it carries, inside the container.
    for c in cs:
        dx(c, "sh", "-c", f"pkill -f {DUTY_LOOP_MARK}; tc qdisc del dev eth0 root 2>/dev/null; true")


PORTS = {"P1": 8081, "P2": 8082, "P3": 8083, "P4": 8084, "P5": 8085, "P0": 8080,
         "none": 8086}


def start_server(srv, profile):
    """A fresh fhirant on its own port, pid recorded for the stop. run3's
    stop (pkill by name) never killed P1's server, so P2 ran on P1's store
    and Bob's wiped keys no longer matched his old key packages there."""
    d = f"/out/{profile}"
    port = PORTS[profile]
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


def stop_server(srv, profile):
    d = f"/out/{profile}"
    port = PORTS[profile]
    # the server's own view of every blob, then the raw store file
    dx(srv, "sh", "-c",
       f"curl -s 'http://127.0.0.1:{port}/Communication?_count=1000&_format=json' > {d}/server_dump.json")
    dx(srv, "sh", "-c",
       f"curl -s 'http://127.0.0.1:{port}/Device?_count=1000&_format=json' > {d}/devices_dump.json")
    dx(srv, "sh", "-c", f"kill -INT $(cat {d}/server.pid); sleep 2; kill -KILL $(cat {d}/server.pid) 2>/dev/null; true", user="0")
    dx(srv, "sh", "-c", f"kill -INT $(cat {d}/tcpdump.pid); sleep 1; true", user="0")
    for _ in range(20):
        if dx(srv, "curl", "-fsS", f"http://127.0.0.1:{port}/health", timeout=10).returncode != 0:
            break
        time.sleep(1)
    else:
        raise RuntimeError(f"server on {port} did not stop")
    dx(srv, "sh", "-c", f"cp /data/{profile}/fhirant.db {d}/fhirant.db", user="0")
    dx(srv, "chown", "-R", f"{os.getuid()}:{os.getgid()}", "/out", user="0")


def start_duty_loop(cs, rate, rtt, loss):
    """P4: 30 s of link, then 60 s of nothing, over and over, on every
    container; killed by clear_shaping through the tag it carries."""
    loop = (f"MARK={DUTY_LOOP_MARK}; while true; do "
            f"tc qdisc replace dev eth0 root netem delay {rtt/2}ms loss {loss}% rate {rate}kbit; "
            f"sleep 30; tc qdisc replace dev eth0 root netem loss 100%; sleep 60; done")
    for c in cs:
        sh(["docker", "exec", "-d", c, "sh", "-c", loop])


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
