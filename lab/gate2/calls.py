#!/usr/bin/env python3
"""Gate 2 calls: one fhirant, one relay (coturn) and two phones running the
app's Linux build in the Docker lab. Alice calls Bob with her screen as the
picture (a test pattern plays full screen on it) and her virtual microphone as
the sound, into which a click track plays once the call connects; Bob's
screen and speaker are recorded.

    python3 lab/gate2/calls.py --label calls1 [--profiles none] [--call-s 30]
                               [--skip-build]
    python3 lab/gate2/calls.py --label calls8 --reanalyse   (files on disk only)

Profiles: `none` (no shaping), P1-P5 and P0 from labkit.PROFILES, and
`plus500`, the instrument check: 500 ms one way on every container and
nothing else, so the voice delay must read about 500 ms more than `none` on
a direct call. `cut20`, `cut60` and `cut120`: no shaping, and 30 s after
Alice's call connects both phones lose their link (100% loss on their own
interfaces; the server and relay keep theirs) for 20, 60 or 120 s, so the
call must reconnect, or with 120 s outlast its 90 s grace and end as lost
on both phones (E8 in docs/GATE2-CALLS-PLAN.md). Any profile with `-blocked` appended (`P2-blocked`) also
blocks the two phones' direct route to each other, so the call must go
through the relay. P5 runs on a second network created with `--internal`
(no route out), as run.py does.

Per profile: a fresh server store and a packet capture on the server; a
fresh relay; Bob waits; Alice calls; both screens and both sound cards are
recorded for the call; then the server's dump. The relay stands for the
deployment's server host, so it is shaped like the server. Both phones are
always given the relay; the route the call took is read from its own stats
and from the relay's log. The DTLS certificate fingerprints both phones used
are then hunted in the server's dump, store and capture
(lab/adversary/canary_scan.py): the call setup that carries them must reach
the server only encrypted.

Raw files land in results/<label>/<profile>/, one summary line per profile
in results/<label>.jsonl, flushed. Recordings (*.mp4, *.mkv, *.wav) stay on
disk only (.gitignore). The networks are created once per run and removed at
the end (labkit's rule: no network churn).

Do not start a run without Grey's go (docs/GATE1.md).
"""
import ipaddress
import json
import os
import shutil
import sys
import time

from labkit import (PORTS, PROFILES, REPO, build_server, clear_shaping, dx,
                    freeze_spans, ip_of,
                    netem, pin_neighbours, sh, start_duty_loop, start_loop, start_server, stop_server, utc)
from voice_delay import click_track_cmd, measure as voice_delay, record_cmd

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(REPO, "app")
BUNDLE = os.path.join(APP, "build", "linux", "x64", "release", "bundle")
CONTEXT = os.path.join(HERE, "build", "calls-context")
SCANNER = os.path.join(REPO, "lab", "adversary", "canary_scan.py")
SUMMARY = os.path.join(HERE, "calls_summary.py")
SRV_IMG = "tremulator-g2-server:latest"
PHONE_IMG = "tremulator-g2-calls:latest"
NETS = {False: "tremulator-g2c-ext", True: "tremulator-g2c-int"}
NODES = {  # internal network?: (server, relay, alice, bob)
    False: ("g2c-srv", "g2c-turn", "g2c-alice", "g2c-bob"),
    True: ("g2c-srv5", "g2c-turn5", "g2c-alice5", "g2c-bob5"),
}
CHECKS = {"plus500": (0, 1000, 0, False)}  # name: as PROFILES
CUTS = {"cut20": 20, "cut60": 60, "cut120": 120}  # name: seconds of no link
CUT_AT_S = 30  # after Alice's call connects
TURN_PORT = 3478


def argval(flag, default):
    return sys.argv[sys.argv.index(flag) + 1] if flag in sys.argv else default


label = argval("--label", time.strftime("calls-%Y%m%d-%H%M"))
profiles = argval("--profiles", "none").split(",")
call_s = int(argval("--call-s", "30"))
outroot = os.path.join(HERE, "results", label)
os.makedirs(outroot, exist_ok=True)
summary = open(os.path.join(HERE, "results", f"{label}.jsonl"), "a")


def log(rec):
    rec = {"run": label, "t": time.strftime("%Y-%m-%dT%H:%M:%S"), **rec}
    summary.write(json.dumps(rec) + "\n")
    summary.flush()
    print(json.dumps(rec), flush=True)


def parse(name):
    """(base profile, shaping or None, internal network?, direct route blocked?)"""
    base, _, variant = name.partition("-")
    if variant not in ("", "blocked"):
        raise ValueError(f"unknown variant in {name}")
    if base == "none":
        shape = None
    elif base == "P0":
        shape = (0, 0, 100, False)
    elif base in PROFILES:
        shape = PROFILES[base]
    elif base in CHECKS:
        shape = CHECKS[base]
    elif base in CUTS:
        shape = None
    else:
        raise ValueError(f"unknown profile {name}")
    return base, shape, bool(shape and shape[3]), variant == "blocked"


def build():
    sh(["flutter", "build", "linux", "--release"], cwd=APP, check=True, timeout=1800)
    shutil.rmtree(CONTEXT, ignore_errors=True)
    os.makedirs(CONTEXT)
    shutil.copytree(BUNDLE, os.path.join(CONTEXT, "bundle"))
    shutil.copy(os.path.join(HERE, "calls_phone.sh"), CONTEXT)
    build_server()
    sh(["docker", "build", "-t", PHONE_IMG, "-f", os.path.join(HERE, "Dockerfile.calls"), CONTEXT],
       check=True, timeout=1800)


def setup(internals):
    teardown()
    for internal in sorted(internals):
        net = NETS[internal]
        sh(["docker", "network", "create", *(["--internal"] if internal else []), net], check=True)
        srv, turn, alice, bob = NODES[internal]
        sh(["docker", "run", "-d", "--rm", "--name", srv, "--network", net, "--cap-add", "NET_ADMIN",
            "-v", f"{outroot}:/out", SRV_IMG], check=True)
        # The relay is the phone image (it carries coturn) with no screen.
        sh(["docker", "run", "-d", "--rm", "--name", turn, "--network", net, "--cap-add", "NET_ADMIN",
            "-v", f"{outroot}:/out", PHONE_IMG, "sleep", "infinity"], check=True)
        for c in (alice, bob):
            sh(["docker", "run", "-d", "--rm", "--name", c, "--network", net, "--cap-add", "NET_ADMIN",
                "-v", f"{outroot}:/out", PHONE_IMG], check=True)
        for c in (alice, bob):
            for _ in range(60):
                if dx(c, "test", "-e", "/tmp/phone-ready", timeout=10).returncode == 0:
                    break
                if dx(c, "test", "-e", "/tmp/phone-failed", timeout=10).returncode == 0:
                    raise RuntimeError(f"{c}: {dx(c, 'cat', '/tmp/phone-failed').stdout}")
                time.sleep(1)
            else:
                raise RuntimeError(f"{c}: screen and sound never ready")
        pin_neighbours(NODES[internal])


def teardown():
    for nodes in NODES.values():
        sh(["docker", "rm", "-f", *nodes])
    for net in NETS.values():
        sh(["docker", "network", "rm", net])


def wait_for(c, path, needle, seconds):
    for _ in range(seconds):
        if dx(c, "grep", "-q", needle, path, timeout=10).returncode == 0:
            return True
        time.sleep(1)
    return False


def tcp_probe(c, ip):
    """What a TCP connect from c to ip's port 1 says. Nothing listens there,
    so an open route answers 'Connection refused'; a blackholed one does not."""
    r = dx(c, "bash", "-c", f"timeout 3 bash -c 'exec 3<>/dev/tcp/{ip}/1' 2>&1; echo exit=$?", timeout=10)
    return r.stdout.strip().splitlines()[-2:] if r.stdout.strip() else [r.stderr.strip()]


def block_direct(alice, bob):
    """Blackhole each phone's route to the other; prove it with a TCP probe
    before and after (known positive: refused before)."""
    a_ip, b_ip = ip_of(alice), ip_of(bob)
    before = tcp_probe(alice, b_ip)
    dx(alice, "ip", "route", "add", "blackhole", f"{b_ip}/32", user="0")
    dx(bob, "ip", "route", "add", "blackhole", f"{a_ip}/32", user="0")
    after = tcp_probe(alice, b_ip)
    refused = lambda lines: any("refused" in l.lower() for l in lines)
    if not refused(before) or refused(after):
        raise RuntimeError(f"direct-route block not proved: before {before}, after {after}")
    return {"probe_before": before, "probe_after": after}


def unblock_direct(alice, bob):
    for c in (alice, bob):
        dx(c, "sh", "-c", "ip route show type blackhole | while read -r _ dst _; do "
                          "ip route del blackhole \"$dst\"; done; true", user="0")


def start_relay(turn, d, internal):
    """A fresh coturn for the profile, long-term credentials lab:lab, its
    log in the profile's directory. Docker's networks are private addresses,
    which the relay is told it may forward to."""
    ip = ip_of(turn)
    subnet = ipaddress.ip_network(
        sh(["docker", "network", "inspect", NETS[internal], "-f",
            "{{(index .IPAM.Config 0).Subnet}}"], check=True).stdout.strip())
    dx(turn, "mkdir", "-p", d)
    sh(["docker", "exec", "-d", turn, "sh", "-c",
        f"turnserver -n --listening-port {TURN_PORT} --listening-ip {ip} --relay-ip {ip} "
        f"--lt-cred-mech --user lab:lab --realm tremulator.lab --no-tls --no-dtls --no-cli "
        f"--min-port 49152 --max-port 49999 --verbose --log-file stdout --simple-log "
        f"--allowed-peer-ip {subnet[0]}-{subnet[-1]} > {d}/turn.log 2>&1 & echo $! > {d}/turn.pid"])
    for _ in range(30):
        if dx(turn, "sh", "-c", f"ss -lun | grep -q '{ip}:{TURN_PORT} '", timeout=10).returncode == 0:
            return f"turn:{ip}:{TURN_PORT}?transport=udp"
        time.sleep(1)
    raise RuntimeError(f"relay on {turn} never listened: {dx(turn, 'tail', '-5', f'{d}/turn.log').stdout}")


def stop_relay(turn, d, host_d):
    dx(turn, "sh", "-c", f"kill -INT $(cat {d}/turn.pid); sleep 1; kill -KILL $(cat {d}/turn.pid) 2>/dev/null; true")
    p = os.path.join(host_d, "turn.log")
    text = open(p, errors="replace").read() if os.path.exists(p) else ""
    return {"relay_allocations": text.count("ALLOCATE processed, success"),
            "relay_log_lines": text.count("\n")}


def run_profile(name):
    base, shape, internal, blocked = parse(name)
    srv, turn, alice, bob = NODES[internal]
    nodes = (srv, turn, alice, bob)
    port = PORTS[base]
    d = f"/out/{name}"
    host_d = os.path.join(outroot, name)
    clear_shaping(nodes)
    unblock_direct(alice, bob)
    block = block_direct(alice, bob) if blocked else None
    if shape is not None:
        rate, rtt, loss, _internal = shape
        for c in nodes:
            netem(c, rate, rtt / 2, loss)
        if base == "P4":
            start_duty_loop(nodes, rate, rtt, loss)
    srv_port = start_server(srv, name, port)
    url = f"http://{ip_of(srv)}:{srv_port}"
    relay = start_relay(turn, d, internal)
    stop = f"{d}/alice.done"
    for c in (alice, bob):
        dx(c, "sh", "-c", f"rm -rf /tmp/state; mkdir -p /tmp/state {d}")
    dx(bob, "rm", "-f", f"{d}/bob.exit", stop)

    sh(["docker", "exec", "-d", bob, "sh", "-c",
        f"/app/tremulator --lab --server {url} --name bob --state /tmp/state --out {d}/bob.jsonl "
        f"--audio --turn '{relay}' --until-file {stop} > {d}/bob.stdout 2>&1; echo $? > {d}/bob.exit"])
    if not wait_for(bob, f"{d}/bob.jsonl", "waiting-for-call", 90):
        # P0 is the known negative: Bob cannot reach the server, so no call
        # can be placed. That is a result, logged; calls8 raised here and
        # left P0 without a summary line.
        stop_server(srv, name, port)
        relay_facts = stop_relay(turn, d, host_d)
        clear_shaping(nodes)
        unblock_direct(alice, bob)
        bob_log = os.path.join(host_d, "bob.jsonl")
        first = open(bob_log).readline().strip() if os.path.exists(bob_log) else None
        log({"profile": name, "placed": False, "bob_exit": read(bob, f"{d}/bob.exit"),
             "bob_first_line": first and json.loads(first), **relay_facts})
        return

    # Both screens are recorded from before the call to after it: Bob's is
    # what arrived, Alice's what was sent, so a freeze on Bob's alone is the
    # link's. The start time is written in the container just before ffmpeg
    # starts, so freezes can be placed against each phone's own connected
    # and ended times (same clock: the containers share the host's). The
    # sound is recorded the same way: Alice's microphone (what went in) and
    # Bob's speaker (what came out), each stamped by ffmpeg with the wall
    # clock: every packet's arrival is logged and the start is derived from
    # them (voice_delay.record_cmd). calls1-calls9-before used the start
    # ffmpeg prints, which was off by up to 722 ms (pulse_stamp_check.py).
    rec_s = call_s + 900
    for c, who in ((bob, "bob"), (alice, "alice")):
        sh(["docker", "exec", "-d", c, "sh", "-c",
            f"date -u +%Y-%m-%dT%H:%M:%S.%NZ > {d}/{who}_record.start; exec ffmpeg -y -loglevel error "
            f"-f x11grab -framerate 30 -video_size 1280x720 -i :0 -t {rec_s} -c:v libx264 "
            f"-preset ultrafast -crf 30 -pix_fmt yuv420p {d}/{who}_screen.mp4 > {d}/{who}_record.log 2>&1"])
    for c, who, source in ((bob, "bob_heard", "speaker.monitor"), (alice, "alice_sent", "mic.monitor")):
        sh(["docker", "exec", "-d", c, "sh", "-c", record_cmd(source, f"{d}/{who}", rec_s)])
    # The test pattern is up and moving before Alice's app starts; once her
    # app's window exists the pattern is raised above it (no window manager:
    # a new window maps on top). calls2 started the pattern 3 s after the
    # app, and Bob received 2.15 s of her still app window as a "freeze".
    # Ubuntu 24.04's xdotool has windowraise but not windowlower (calls3).
    sh(["docker", "exec", "-d", alice, "sh", "-c",
        "ffplay -loglevel error -noborder -left 0 -top 0 -x 1280 -y 720 -an "
        "-f lavfi 'testsrc2=size=1280x720:rate=30' > /tmp/ffplay.log 2>&1"])
    time.sleep(2)
    t0 = time.time()
    sh(["docker", "exec", "-d", alice, "sh", "-c",
        f"/app/tremulator --lab --server {url} --name alice --state /tmp/state --out {d}/alice.jsonl "
        f"--peer bob --video --audio --turn '{relay}' --call-s {call_s} "
        f"> {d}/alice.stdout 2>&1; echo $? > {d}/alice.exit"])
    # calls6 `none`: the raise ran, yet her app window ended on top and both
    # screens were grey all call. The raise is now repeated until the stack
    # itself shows the pattern above her window, and the stack is read again
    # when the call connects.
    raised = raise_pattern(alice, 40)
    # The click track starts when Alice's call connects: a 30 ms tone 5 s
    # into every 10 s, ending before her call does.
    clicks = max(1, call_s // 10 - 1)
    clicked = wait_for(alice, f"{d}/alice.jsonl", '"event": *"connected"', 90)
    on_top_at_connect = pattern_on_top(alice)
    if not on_top_at_connect:
        raise_pattern(alice, 8)
    if clicked and base in CUTS:
        cut_links((alice, bob), d, CUTS[base])
    if clicked:
        track = " ".join(click_track_cmd("/tmp/click.wav", clicks))
        sh(["docker", "exec", "-d", alice, "sh", "-c",
            f"{track} && paplay --device=mic /tmp/click.wav > {d}/click.log 2>&1"])
    for _ in range(call_s + 240):
        if dx(alice, "test", "-e", f"{d}/alice.exit", timeout=10).returncode == 0:
            break
        time.sleep(1)
    alice_s = round(time.time() - t0, 1)
    # The recordings run until Bob's call has ended too, then 5 s more, and
    # are stopped with SIGINT so ffmpeg closes the files. calls8 P1: Bob
    # heard the hang-up 61 s after Alice sent it, past a fixed-length
    # recording's end. rec_s is only a cap.
    bob_ended = wait_for(bob, f"{d}/bob.jsonl", '"event": *"call-ended"', 300)
    time.sleep(5)
    for c in (alice, bob):
        dx(c, "sh", "-c", "pkill -INT -x ffmpeg; true")
    dx(alice, "sh", "-c", "pkill -x ffplay; true")
    for c in (alice, bob):
        for _ in range(60):
            if dx(c, "pgrep", "-x", "ffmpeg", timeout=10).returncode != 0:
                break
            time.sleep(1)
    dx(bob, "touch", stop)
    for _ in range(120):
        if dx(bob, "test", "-e", f"{d}/bob.exit", timeout=10).returncode == 0:
            break
        time.sleep(1)
    stop_server(srv, name, port)
    relay_facts = stop_relay(turn, d, host_d)
    clear_shaping(nodes)
    unblock_direct(alice, bob)
    dx(srv, "chown", "-R", f"{os.getuid()}:{os.getgid()}", "/out", user="0")

    rec = {"profile": name, "alice_wall_s": alice_s, "pattern_raised": raised,
           "pattern_on_top_at_connect": on_top_at_connect,
           "direct_blocked": block, "clicks_started": clicked, "bob_call_ended_seen": bob_ended,
           "alice_exit": read(alice, f"{d}/alice.exit"), "bob_exit": read(bob, f"{d}/bob.exit"),
           **relay_facts}
    for line in sh(["python3", "-I", SUMMARY, os.path.join(host_d, "alice.jsonl"),
                    os.path.join(host_d, "bob.jsonl")]).stdout.splitlines():
        s = json.loads(line)
        who = "alice" if s["log"].endswith("alice.jsonl") else "bob"
        rec[who] = {k: v for k, v in s.items() if k != "log"}
    rec["recording_bob"] = recording_facts(host_d, "bob")
    rec["recording_alice"] = recording_facts(host_d, "alice")
    rec["voice"] = voice_facts(host_d)
    if base in CUTS:
        rec["cut"] = cut_facts(host_d, CUTS[base])
    rec.update(fingerprint_hunt(host_d))
    log(rec)


def cut_links(phones, d, seconds):
    """CUT_AT_S from now, each phone's own interface drops every packet for
    `seconds`, then is cleared; the times are written beside the logs. Runs
    in each container, as root (tc), its pid recorded for clear_shaping."""
    for c in phones:
        who = c.split("-")[-1].rstrip("5")
        # Each time is written to a temporary file and renamed, so a loop
        # killed mid-write by clear_shaping leaves no file rather than an
        # empty one (calls10 cut120-blocked: the cut ended as the profile's
        # clean-up ran, and an empty bob_cut.end stopped the run).
        start_loop(c, f"sleep {CUT_AT_S}; date +%s.%N > {d}/{who}_cut.start.tmp && "
                      f"mv {d}/{who}_cut.start.tmp {d}/{who}_cut.start; "
                      f"tc qdisc replace dev eth0 root netem loss 100%; sleep {seconds}; "
                      f"tc qdisc del dev eth0 root; date +%s.%N > {d}/{who}_cut.end.tmp && "
                      f"mv {d}/{who}_cut.end.tmp {d}/{who}_cut.end")


def cut_facts(host_d, seconds):
    """When each phone's link went and came back, and the clicks sent before
    the cut and after it with how many were heard (voice_delay.jsonl)."""
    times = {}
    for who in ("alice", "bob"):
        for edge in ("start", "end"):
            p = os.path.join(host_d, f"{who}_cut.{edge}")
            text = open(p).read().strip() if os.path.exists(p) else ""
            # No time: the loop was killed first (the profile ended before
            # the cut did, and its clean-up restored the link).
            times[f"{who}_{edge}"] = float(text) if text else None
    out = {"planned_s": seconds, **times}
    starts = [times[f"{w}_start"] for w in ("alice", "bob") if times[f"{w}_start"]]
    ends = [times[f"{w}_end"] for w in ("alice", "bob") if times[f"{w}_end"]]
    pairs_p = os.path.join(host_d, "voice_delay.jsonl")
    if starts and ends and os.path.exists(pairs_p):
        pairs = [json.loads(l) for l in open(pairs_p)]
        before = [p for p in pairs if p["sent"] < min(starts)]
        after = [p for p in pairs if p["sent"] > max(ends)]
        heard_after = sorted(p["delay_ms"] for p in after if p["delay_ms"] is not None)
        out.update({
            "clicks_before": len(before),
            "heard_before": sum(p["delay_ms"] is not None for p in before),
            "clicks_after": len(after), "heard_after": len(heard_after),
            "first_heard_after_s": next((round(p["sent"] - max(ends), 1) for p in after
                                         if p["delay_ms"] is not None), None),
            "delay_after_median_ms": heard_after[len(heard_after) // 2] if heard_after else None})
    return out


def pattern_on_top(c):
    """True when the test pattern is above the app's window. xwininfo lists
    the root's children top of the stack first (checked in the phone image:
    a later window is listed first, and a raised one moves to the front)."""
    out = dx(c, "xwininfo", "-root", "-children", timeout=10).stdout
    for line in out.splitlines():
        if '("ffplay"' in line:
            return True
        if '"tremulator"' in line:
            return False
    return False


def raise_pattern(c, tries):
    """Once the app's window is visible, raise the pattern until the stack
    shows it on top, every 0.25 s for up to `tries` attempts."""
    for _ in range(tries):
        if dx(c, "xdotool", "search", "--onlyvisible", "--name", "^tremulator$",
              timeout=10).returncode == 0:
            dx(c, "xdotool", "search", "--class", "ffplay", "windowraise", timeout=10)
            if pattern_on_top(c):
                return True
        time.sleep(0.25)
    return False


def read(c, path):
    return dx(c, "cat", path, timeout=10).stdout.strip() or None


def voice_facts(host_d):
    """One-way voice delay per click (voice_delay.py), or why there is none."""
    sent, heard = (os.path.join(host_d, f) for f in ("alice_sent.mkv", "bob_heard.mkv"))
    if not (os.path.exists(sent) and os.path.exists(heard)):
        return {"missing": [os.path.basename(p) for p in (sent, heard) if not os.path.exists(p)]}
    try:
        return voice_delay(sent, heard, os.path.join(host_d, "voice_delay.jsonl"))
    except RuntimeError as e:
        return {"error": str(e)[:500]}


def recording_facts(host_d, who):
    """Frozen video on one phone's screen during the call, by ffmpeg
    freezedetect (the Gate 1 instrument), from that phone's connected line
    to the FIRST call-ended line of either phone (media stops when either
    hangs up; calls8 P1's Bob logged the end 61 s after Alice and was
    divided by his longer call), clipped to the recording; plus three stills
    from the call to look at."""
    mp4 = os.path.join(host_d, f"{who}_screen.mp4")
    start_file = os.path.join(host_d, f"{who}_record.start")
    if not os.path.exists(mp4) or not os.path.exists(start_file):
        return None
    length = float(sh(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                       "-of", "csv=p=0", mp4]).stdout.strip())
    # Gate 1's settings exactly (lab/baseline/README.md): n=-60dB, d=0.5.
    fd = sh(["ffmpeg", "-hide_banner", "-i", mp4, "-vf", "freezedetect=n=-60dB:d=0.5", "-map", "0:v",
             "-f", "null", "-"], timeout=600).stderr
    with open(mp4[:-4] + "_freezedetect.txt", "w") as f:
        f.write(fd)
    rec_start = utc(open(start_file).read())
    events = [json.loads(l) for l in open(os.path.join(host_d, f"{who}.jsonl"))]
    conn = next((e for e in events if e["event"] == "connected"), None)
    ends = []
    for w in ("alice", "bob"):
        p = os.path.join(host_d, f"{w}.jsonl")
        if os.path.exists(p):
            ends += [utc(json.loads(l)["t"]) for l in open(p) if '"call-ended"' in l]
    if conn is None or not ends:
        return {"length_s": length, "call_window": None}
    a, b_end = utc(conn["t"]) - rec_start, min(ends) - rec_start
    b = min(b_end, length)
    inside = [(max(s0, a), min(s1, b)) for s0, s1 in freeze_spans(fd, length) if s1 > a and s0 < b]
    frozen = sum(s1 - s0 for s0, s1 in inside)
    call = b - a
    stills = []
    for frac in (0.25, 0.5, 0.75):
        png = f"{mp4[:-4]}_{int(frac * 100)}.png"
        sh(["ffmpeg", "-y", "-loglevel", "error", "-ss", str(a + call * frac), "-i", mp4,
            "-frames:v", "1", png])
        stills.append(os.path.basename(png))
    return {"length_s": length, "call_window_s": [round(a, 2), round(b, 2)],
            "window_cut_by_recording_s": round(b_end - b, 2),
            "hangup_lag_s": round(max(ends) - min(ends), 2) if len(ends) > 1 else None,
            "freezes": len(inside), "frozen_s": round(frozen, 2),
            "frozen_s_per_min": round(frozen / call * 60, 2) if call > 0 else None,
            "stills": stills}


def fingerprint_hunt(host_d):
    """The DTLS certificate fingerprints, as the stats name them, hunted in
    what the server holds and what crossed its interface."""
    fps = set()
    for who in ("alice", "bob"):
        p = os.path.join(host_d, f"{who}.jsonl")
        if not os.path.exists(p):
            continue
        for l in open(p):
            e = json.loads(l)
            for r in e.get("reports", []):
                for k in ("localCertificateId", "remoteCertificateId"):
                    v = r.get(k)
                    if isinstance(v, str) and v.startswith("CF"):
                        fps.add(v[2:])
    tsv = os.path.join(host_d, "fingerprints.tsv")
    with open(tsv, "w") as f:
        for i, fp in enumerate(sorted(fps)):
            f.write(f"{i}\t{fp}\n")
    hits = os.path.join(host_d, "fingerprint_hits.jsonl")
    evidence = [os.path.join(host_d, f) for f in
                ("server_dump.json", "devices_dump.json", "fhirant.db", "traffic.pcap", "server.log")]
    evidence = [f for f in evidence if os.path.exists(f)]
    scan = sh(["python3", "-I", SCANNER, tsv, hits, *evidence], timeout=1800)
    # Positive control: the phones' own logs hold the fingerprints, so the
    # scanner must find them there, or a clean result above means nothing.
    control = os.path.join(host_d, "fingerprint_control_hits.jsonl")
    sh(["python3", "-I", SCANNER, tsv, control, os.path.join(host_d, "alice.jsonl")], timeout=600)
    def count(p):
        return sum(1 for _ in open(p)) if os.path.exists(p) else None
    return {"fingerprints": len(fps), "fingerprint_scan_exit": scan.returncode,
            "fingerprint_hits": count(hits), "fingerprint_control_hits": count(control)}


def reanalyse():
    """`--reanalyse --label L`: the frozen-video and voice numbers again from
    a finished run's files on disk, with today's code, into
    results/L-reanalysed.jsonl. Nothing runs in Docker."""
    out = open(os.path.join(HERE, "results", f"{label}-reanalysed.jsonl"), "a")
    for l in open(os.path.join(HERE, "results", f"{label}.jsonl")):
        r = json.loads(l)
        if "profile" not in r:
            continue
        host_d = os.path.join(outroot, r["profile"])
        rec = {"run": label, "profile": r["profile"], "reanalysed": time.strftime("%Y-%m-%dT%H:%M:%S"),
               "recording_bob": recording_facts(host_d, "bob"),
               "recording_alice": recording_facts(host_d, "alice"),
               "voice": voice_facts(host_d)}
        out.write(json.dumps(rec) + "\n")
        out.flush()
        print(json.dumps(rec), flush=True)


if __name__ == "__main__":
    if "--reanalyse" in sys.argv:
        reanalyse()
        sys.exit(0)
    for name in profiles:
        parse(name)  # an unknown name fails before anything is built
    if "--skip-build" not in sys.argv:
        build()
    log({"event": "start", "profiles": profiles, "call_s": call_s})
    try:
        setup({parse(n)[2] for n in profiles})
        for name in profiles:
            run_profile(name)
    finally:
        teardown()
        log({"event": "end"})
