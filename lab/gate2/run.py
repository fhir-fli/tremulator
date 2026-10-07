#!/usr/bin/env python3
"""Gate 2 text measurements: one fhirant and two tremulator clients in the
Docker lab, across the network profiles of docs/SUCCESS.md.

    python3 lab/gate2/run.py --label run1 [--profiles P1,P2] [--messages 20]
                             [--interval-ms 1000] [--skip-build]

Per profile: a fresh server store, a packet capture on the server, Bob
listening, Alice opening a conversation and sending N messages with a canary
word in each; then the server's own view of every Communication is dumped and
the canary scanner (lab/adversary/canary_scan.py) hunts the canaries in the
dump, the store file and the capture. Every result line is appended to
results/<label>.jsonl and flushed; raw files land in results/<label>/<profile>/.

Network setup follows lab/network/validate.py: two networks and one
container trio each, created ONCE per run and reused; only tc changes between
profiles (the 2026-09-21 incident was network churn). The P4 duty cycle and P0
dead link are the same tc loops. Every pkill here runs INSIDE a container
through docker exec, never on the host.

Do not start a run without Grey's go (docs/GATE1.md).
"""
import json
import os
import secrets
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FHIRANT = os.path.abspath(os.path.join(REPO, "..", "fhirant"))
CLIENT_PKG = os.path.join(REPO, "packages", "tremulator_client")
SCANNER = os.path.join(REPO, "lab", "adversary", "canary_scan.py")

PROFILES = {  # name: (rate_kbit, rtt_ms, loss_pct, internal_network)
    "P1": (50, 400, 5, False),
    "P2": (300, 200, 2, False),
    "P3": (1000, 700, 1, False),
    "P4": (300, 250, 2, False),
    "P5": (10000, 5, 0, True),
}
NETS = {False: "tremulator-g2-ext", True: "tremulator-g2-int"}
TRIOS = {
    False: ("g2-srv", "g2-alice", "g2-bob"),
    True: ("g2-srv5", "g2-alice5", "g2-bob5"),
}
SRV_IMG = "tremulator-g2-server:latest"
CLI_IMG = "tremulator-g2-client:latest"
DUTY_LOOP_MARK = "tremulator-duty-loop"  # a tag the loop carries, for its kill


def argval(flag, default):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


label = argval("--label", time.strftime("run-%Y%m%d-%H%M"))
profiles = argval("--profiles", "P1,P2,P3,P4,P5,P0").split(",")
messages = int(argval("--messages", "20"))
interval_ms = int(argval("--interval-ms", "1000"))
outroot = os.path.join(HERE, "results", label)
os.makedirs(outroot, exist_ok=True)
summary = open(os.path.join(HERE, "results", f"{label}.jsonl"), "a")


def log(rec):
    rec = {"run": label, "t": time.strftime("%Y-%m-%dT%H:%M:%S"), **rec}
    summary.write(json.dumps(rec) + "\n")
    summary.flush()
    print(json.dumps(rec), flush=True)


def sh(cmd, timeout=600, check=False, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, **kw)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}: {r.stderr.strip()}")
    return r


def dx(c, *args, timeout=600, user=None):
    u = ["-u", user] if user else []
    return sh(["docker", "exec", *u, c, *args], timeout=timeout)


def build():
    sh(["dart", "build", "cli", "-o", "build/cli"], cwd=CLIENT_PKG, check=True, timeout=1200)
    sh(["docker", "build", "-t", "fhirant:latest", FHIRANT], check=True, timeout=3600)
    sh(["docker", "build", "-t", SRV_IMG, "-f", os.path.join(HERE, "Dockerfile.server"), HERE],
       check=True, timeout=1200)
    sh(["docker", "build", "-t", CLI_IMG, "-f", os.path.join(HERE, "Dockerfile.client"), CLIENT_PKG],
       check=True, timeout=1200)


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


def setup_all():
    teardown_all()
    for internal, net in NETS.items():
        sh(["docker", "network", "create", *(["--internal"] if internal else []), net], check=True)
        srv, a, b = TRIOS[internal]
        sh(["docker", "run", "-d", "--rm", "--name", srv, "--network", net, "--cap-add", "NET_ADMIN",
            "-v", f"{outroot}:/out", SRV_IMG], check=True)
        for c in (a, b):
            sh(["docker", "run", "-d", "--rm", "--name", c, "--network", net, "--cap-add", "NET_ADMIN",
                "-v", f"{outroot}:/out", CLI_IMG], check=True)
        pin_neighbours(TRIOS[internal])
    time.sleep(1)


def teardown_all():
    for trio in TRIOS.values():
        sh(["docker", "rm", "-f", *trio])
    for net in NETS.values():
        sh(["docker", "network", "rm", net])


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


PORTS = {"P1": 8081, "P2": 8082, "P3": 8083, "P4": 8084, "P5": 8085, "P0": 8080}


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


def client_running(c, marker):
    """Bob is done when the exit-code file his shell writes after him exists.
    run2 waited on pgrep by process name and returned early (summary logged
    13 s before Bob's last line; P1 counted 14 of a real 20)."""
    return dx(c, "test", "-e", marker, timeout=10).returncode != 0


def run_profile(name, rate, rtt, loss, internal, dead=False):
    srv, alice, bob = TRIOS[internal]
    clear_shaping((srv, alice, bob))
    for c in (srv, alice, bob):
        netem(c, rate, rtt / 2, 100 if dead else loss)
    if name == "P4":
        loop = (f"MARK={DUTY_LOOP_MARK}; while true; do "
                f"tc qdisc replace dev eth0 root netem delay {rtt/2}ms loss {loss}% rate {rate}kbit; "
                f"sleep 30; tc qdisc replace dev eth0 root netem loss 100%; sleep 60; done")
        for c in (srv, alice, bob):
            sh(["docker", "exec", "-d", c, "sh", "-c", loop])
    port = start_server(srv, name)
    url = f"http://{ip_of(srv)}:{port}"
    d = f"/out/{name}"
    canary = "canary-" + secrets.token_hex(6)
    listen_s = 45 if dead else max(60, int(messages * interval_ms / 1000) + 90)
    stop = f"{d}/alice.done"
    for c in (alice, bob):
        dx(c, "sh", "-c", f"rm -rf /state; mkdir -p /state; mkdir -p {d}")
    dx(bob, "sh", "-c", f"rm -f {d}/bob.exit {stop}")
    sh(["docker", "exec", "-d", bob, "sh", "-c",
        f"/client/bin/tremulator_client --server {url} --name bob --state /state --out {d}/bob.jsonl "
        f"--listen-s {listen_s} --until-file {stop} --timeout-s 60 > {d}/bob.stdout 2>&1; echo $? > {d}/bob.exit"])
    time.sleep(5)
    t0 = time.time()
    r = dx(alice, "sh", "-c",
           f"/client/bin/tremulator_client --server {url} --name alice --state /state "
           f"--out {d}/alice.jsonl --peer bob --send {messages} --interval-ms {interval_ms} "
           f"--listen-s 20 --timeout-s 60 --canary {canary} > {d}/alice.stdout 2>&1",
           timeout=listen_s + 600)
    alice_s = round(time.time() - t0, 1)
    # Alice is done: give Bob one more wake-up and collect, then the stop sign.
    time.sleep(30 if not dead else 5)
    dx(bob, "sh", "-c", f"touch {stop}")
    for _ in range(listen_s + 300):
        if not client_running(bob, f"{d}/bob.exit"):
            break
        time.sleep(1)
    bob_exit = dx(bob, "cat", f"{d}/bob.exit", timeout=10).stdout.strip()
    stop_server(srv, name)
    clear_shaping((srv, alice, bob))
    # the plaintext hunt
    canaries = os.path.join(outroot, name, "canaries.tsv")
    with open(canaries, "w") as f:
        for i in range(messages):
            f.write(f"{i}\t{canary}-{i}\n")
    hits = os.path.join(outroot, name, "canary_hits.jsonl")
    # Scan the evidence files by name: never the canary list or the hit list
    # themselves (run1 scanned the directory and found its own list, 40 hits).
    evidence = [os.path.join(outroot, name, f) for f in
                ("server_dump.json", "devices_dump.json", "fhirant.db", "traffic.pcap",
                 "server.log", "alice.jsonl", "bob.jsonl", "alice.stdout", "bob.stdout")]
    evidence = [f for f in evidence if os.path.exists(f)]
    scan = sh(["python3", "-I", SCANNER, canaries, hits, *evidence], timeout=1800)
    rec = summarize(name, os.path.join(outroot, name))
    rec.update({"alice_exit": r.returncode, "alice_wall_s": alice_s, "bob_exit": bob_exit,
                "canary_scan_exit": scan.returncode,
                "canary_hits": sum(1 for _ in open(hits)) if os.path.exists(hits) else None})
    log(rec)


def summarize(profile, d):
    """Delivery and timing from the two JSON-lines logs."""
    def lines(fn):
        p = os.path.join(d, fn)
        return [json.loads(l) for l in open(p)] if os.path.exists(p) else []
    a, b = lines("alice.jsonl"), lines("bob.jsonl")
    sent = [e for e in a if e["event"] == "sent"]
    got = [e for e in b if e["event"] == "received"]
    lat = sorted(e["one-way-ms"] for e in got if e.get("one-way-ms") is not None)
    med = lat[len(lat) // 2] if lat else None
    return {"profile": profile, "sent": len(sent), "delivered": len(got),
            "one_way_median_ms": med, "one_way_max_ms": lat[-1] if lat else None,
            "send_failed": sum(1 for e in a if e["event"] == "send-failed"),
            "open_failed": sum(1 for e in a if e["event"] == "open-failed"),
            "joined": sum(1 for e in b if e["event"] == "joined"),
            "out_of_step": sum(1 for e in a + b if e["event"] == "out-of-step"),
            "undecryptable": sum(1 for e in a + b if e["event"] == "undecryptable"),
            "collect_failed": sum(1 for e in a + b if e["event"] == "collect-failed"),
            "bob_listen_mode": "poll" if any(e["event"] == "listen-failed" for e in b) else "wake-up"}


if __name__ == "__main__":
    if "--skip-build" not in sys.argv:
        build()
    log({"event": "start", "profiles": profiles, "messages": messages, "interval_ms": interval_ms})
    try:
        setup_all()
        for name in profiles:
            if name == "P0":
                run_profile("P0", 0, 0, 0, False, dead=True)
            else:
                run_profile(name, *PROFILES[name])
    finally:
        teardown_all()
        log({"event": "end"})
