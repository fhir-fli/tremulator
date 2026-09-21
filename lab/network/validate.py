#!/usr/bin/env python3
"""Validate the tremulator network profiles (docs/GATE1.md).

Usage: validate.py RUN_LABEL
For each profile: create a Docker network and two containers (server, client)
with NET_ADMIN, apply tc netem on both eth0s, measure RTT, delivered UDP rate
and one-way loss, plus the P4 duty cycle, the P5 no-internet check (and its
known-positive control), and the P0 zero-link check. Every measurement is
appended to results/<RUN_LABEL>.jsonl and flushed. Containers and networks are
removed afterwards, including on failure.
"""
import json, math, os, re, statistics, subprocess, sys, time

IMG = "tremulator-lab:latest"
SRV, CLI = "tlab-srv", "tlab-cli"
PAYLOAD_RATE, PAYLOAD_LOSS = 1000, 64       # UDP payload bytes for rate / loss tests
OVERHEAD = 42                               # UDP 8 + IPv4 20 + Ethernet 14 bytes

PROFILES = {  # name: (rate_kbit, rtt_ms, loss_pct, internal_network)
    "P1": (50, 400, 5.0, False),
    "P2": (300, 200, 2.0, False),
    "P3": (1000, 700, 1.0, False),
    "P4": (300, 250, 2.0, False),
    "P5": (10000, 5, 0.0, True),
}

label = sys.argv[1]
os.makedirs("results", exist_ok=True)
out = open(f"results/{label}.jsonl", "a")

def log(rec):
    rec["t"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    out.write(json.dumps(rec) + "\n"); out.flush()
    print(json.dumps(rec), flush=True)

def sh(cmd, timeout=600, check=False):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"{cmd}: {r.returncode} {r.stderr.strip()}")
    return r

def dx(c, *args, timeout=600):
    return sh(["docker", "exec", c, *args], timeout=timeout)

def netem(c, rate, delay_ms, loss, verb="replace"):
    args = ["tc", "qdisc", verb, "dev", "eth0", "root", "netem",
            "delay", f"{delay_ms}ms", "loss", f"{loss}%"]
    if rate:
        args += ["rate", f"{rate}kbit"]
    r = dx(c, *args)
    if r.returncode != 0:
        raise RuntimeError(f"netem on {c}: {r.stderr.strip()}")

def up(net, internal):
    teardown(net)
    sh(["docker", "network", "create", *(["--internal"] if internal else []), net], check=True)
    for c in (SRV, CLI):
        sh(["docker", "run", "-d", "--rm", "--name", c, "--network", net,
            "--cap-add", "NET_ADMIN", IMG], check=True)
    dx(SRV, "iperf3", "-s", "-D")
    time.sleep(1)

def teardown(net):
    sh(["docker", "rm", "-f", SRV, CLI])
    sh(["docker", "network", "rm", net])

def srv_ip():
    r = dx(SRV, "sh", "-c", "ip -4 -o addr show eth0 | awk '{print $4}' | cut -d/ -f1")
    return r.stdout.strip()

def wilson(k, n, z=1.96):
    if n == 0: return (0.0, 1.0)
    p = k / n; d = 1 + z*z/n
    c = (p + z*z/(2*n)) / d; h = z*math.sqrt(p*(1-p)/n + z*z/(4*n*n)) / d
    return (max(0.0, c-h), min(1.0, c+h))

def ping_rtts(ip, count=100, interval=0.2):
    r = dx(CLI, "ping", "-n", "-c", str(count), "-i", str(interval), "-s", "16", "-W", "3", ip,
           timeout=count*interval + 60)
    rtts = [float(x) for x in re.findall(r"time=([\d.]+) ms", r.stdout)]
    return rtts

def iperf_udp(ip, rate_bps, length, secs):
    r = dx(CLI, "iperf3", "-c", ip, "-u", "-b", str(int(rate_bps)), "-l", str(length),
           "-t", str(secs), "-J", timeout=secs + 120)
    try:
        j = json.loads(r.stdout)
    except ValueError:
        return {"error": (r.stdout + r.stderr)[-300:]}
    if "error" in j:
        return {"error": j["error"]}
    # Receiver-side figures. end.sum / end.sum_sent carry the SENDER's rate; the
    # first version read end.sum and reported 60 kbit/s delivered on a 50 kbit/s
    # link (2026-09-21). end.sum_received is what arrived.
    s = j["end"].get("sum_received") or j["end"]["sum"]
    return {"bps": s.get("bits_per_second"), "lost": s.get("lost_packets"),
            "packets": s.get("packets"), "seconds": s.get("seconds"),
            "sent_bps": j["end"].get("sum_sent", {}).get("bits_per_second")}

def steady(name, rate, rtt, loss):
    ip = srv_ip()
    rtts = ping_rtts(ip)
    med = statistics.median(rtts) if rtts else None
    ok = med is not None and abs(med - rtt) <= 0.10 * rtt
    log({"run": label, "profile": name, "metric": "rtt_ms", "target": rtt, "median": med,
         "n_replies": len(rtts), "pass": ok})
    # delivered rate
    exp_bps = rate * 1000 * PAYLOAD_RATE / (PAYLOAD_RATE + OVERHEAD) * (1 - loss/100)
    u = iperf_udp(ip, rate * 1000 * 1.2, PAYLOAD_RATE, 30)
    ok = "bps" in u and u["bps"] is not None and abs(u["bps"] - exp_bps) <= 0.10 * exp_bps
    log({"run": label, "profile": name, "metric": "delivered_bps", "expected": exp_bps, **u, "pass": ok})
    # one-way loss
    pps = rate * 1000 * 0.5 / ((PAYLOAD_LOSS + OVERHEAD) * 8)
    secs = max(15, math.ceil(2000 / pps) + 2)
    u = iperf_udp(ip, rate * 1000 * 0.5, PAYLOAD_LOSS, secs)
    if "packets" in u and u["packets"]:
        lo, hi = wilson(u["lost"], u["packets"])
        ok = lo <= loss/100 <= hi and u["packets"] >= 2000
        log({"run": label, "profile": name, "metric": "loss", "target_pct": loss,
             "measured_pct": 100*u["lost"]/u["packets"], "ci95_pct": [100*lo, 100*hi], **u, "pass": ok})
    else:
        log({"run": label, "profile": name, "metric": "loss", "target_pct": loss, **u, "pass": False})

def internet_probe():
    r = dx(CLI, "ping", "-n", "-c", "3", "-W", "2", "1.1.1.1", timeout=30)
    return r.returncode == 0

try:
    for name, (rate, rtt, loss, internal) in PROFILES.items():
        net = f"tlab-{name.lower()}"
        up(net, internal)
        try:
            for c in (SRV, CLI):
                netem(c, rate, rtt/2, loss)
            steady(name, rate, rtt, loss)
            if name == "P2":   # known-positive control for the internet check
                reach = internet_probe()
                log({"run": label, "profile": name, "metric": "internet_reachable_control",
                     "reachable": reach, "pass": reach})
            if name == "P5":
                reach = internet_probe()
                log({"run": label, "profile": name, "metric": "no_internet",
                     "reachable": reach, "pass": not reach})
            if name == "P4":
                # duty cycle: 30 s up, 60 s down, on both ends, two cycles
                loop = (f"while true; do tc qdisc replace dev eth0 root netem delay {rtt/2}ms loss {loss}% rate {rate}kbit; "
                        f"sleep 30; tc qdisc replace dev eth0 root netem loss 100%; sleep 60; done")
                for c in (SRV, CLI):
                    sh(["docker", "exec", "-d", c, "sh", "-c", loop])
                t0 = time.time()
                r = dx(CLI, "ping", "-n", "-D", "-i", "0.2", "-W", "1", "-w", "185", srv_ip(), timeout=240)
                stamps = [float(x) for x in re.findall(r"^\[([\d.]+)\].*time=", r.stdout, re.M)]
                ups, downs, start = [], [], None
                for a, b in zip(stamps, stamps[1:]):
                    if start is None: start = a
                    if b - a > 2.0:
                        ups.append(a - start); downs.append(b - a); start = None
                if start is not None and stamps: ups.append(stamps[-1] - start)
                full_ups = ups[1:-1] if len(ups) > 2 else ups   # first/last windows may be cut by the probe start/end
                ok_up = bool(full_ups) and all(abs(u - 30) <= 3 for u in full_ups)
                ok_dn = bool(downs) and all(abs(d - 60) <= 6 for d in downs)
                log({"run": label, "profile": name, "metric": "duty_cycle", "up_windows_s": [round(u,1) for u in ups],
                     "down_gaps_s": [round(d,1) for d in downs], "judged_up": [round(u,1) for u in full_ups],
                     "pass": ok_up and ok_dn})
        finally:
            teardown(net)
    # P0: the zero link must fail
    net = "tlab-p0"; up(net, False)
    try:
        for c in (SRV, CLI):
            netem(c, 0, 0, 100)
        rtts = ping_rtts(srv_ip(), count=20)
        u = iperf_udp(srv_ip(), 100000, 64, 5)
        failed = len(rtts) == 0 and ("error" in u or not u.get("bps"))
        log({"run": label, "profile": "P0", "metric": "zero_link_fails", "ping_replies": len(rtts),
             "iperf": u, "pass": failed})
    finally:
        teardown(net)
finally:
    out.close()
print("DONE", flush=True)
