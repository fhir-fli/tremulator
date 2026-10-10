#!/usr/bin/env python3
"""Gate 2 calls: one fhirant and two phones running the app's Linux build in
the Docker lab. Alice calls Bob with her screen as the picture (a test
pattern plays full screen on it) and her virtual microphone as the sound;
Bob's screen shows what arrives and is recorded.

    python3 lab/gate2/calls.py --label calls1 [--profiles none] [--call-s 30]
                               [--skip-build]

Profiles: `none` (no shaping) and P1-P5, P0 from labkit.PROFILES. Per
profile: a fresh server store and a packet capture on the server; Bob waits;
Alice calls; Bob's screen is recorded for the call; then the server's dump.
The DTLS certificate fingerprints both phones used are then hunted in the
server's dump, store and capture (lab/adversary/canary_scan.py): the call
setup that carries them must reach the server only encrypted.

Raw files land in results/<label>/<profile>/, one summary line per profile
in results/<label>.jsonl, flushed. One network, created once per run and
removed at the end (labkit's rule: no network churn).

Do not start a run without Grey's go (docs/GATE1.md).
"""
import json
import os
import shutil
import sys
import time

from labkit import (PROFILES, REPO, build_server, clear_shaping, dx, freeze_spans, ip_of, netem,
                    pin_neighbours, sh, start_duty_loop, start_server, stop_server, utc)

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(REPO, "app")
BUNDLE = os.path.join(APP, "build", "linux", "x64", "release", "bundle")
CONTEXT = os.path.join(HERE, "build", "calls-context")
SCANNER = os.path.join(REPO, "lab", "adversary", "canary_scan.py")
SUMMARY = os.path.join(HERE, "calls_summary.py")
SRV_IMG = "tremulator-g2-server:latest"
PHONE_IMG = "tremulator-g2-calls:latest"
NET = "tremulator-g2c-ext"
SRV, ALICE, BOB = "g2c-srv", "g2c-alice", "g2c-bob"


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


def build():
    sh(["flutter", "build", "linux", "--release"], cwd=APP, check=True, timeout=1800)
    shutil.rmtree(CONTEXT, ignore_errors=True)
    os.makedirs(CONTEXT)
    shutil.copytree(BUNDLE, os.path.join(CONTEXT, "bundle"))
    shutil.copy(os.path.join(HERE, "calls_phone.sh"), CONTEXT)
    build_server()
    sh(["docker", "build", "-t", PHONE_IMG, "-f", os.path.join(HERE, "Dockerfile.calls"), CONTEXT],
       check=True, timeout=1800)


def setup():
    teardown()
    sh(["docker", "network", "create", NET], check=True)
    sh(["docker", "run", "-d", "--rm", "--name", SRV, "--network", NET, "--cap-add", "NET_ADMIN",
        "-v", f"{outroot}:/out", SRV_IMG], check=True)
    for c in (ALICE, BOB):
        sh(["docker", "run", "-d", "--rm", "--name", c, "--network", NET, "--cap-add", "NET_ADMIN",
            "-v", f"{outroot}:/out", PHONE_IMG], check=True)
    for c in (ALICE, BOB):
        for _ in range(60):
            if dx(c, "test", "-e", "/tmp/phone-ready", timeout=10).returncode == 0:
                break
            if dx(c, "test", "-e", "/tmp/phone-failed", timeout=10).returncode == 0:
                raise RuntimeError(f"{c}: {dx(c, 'cat', '/tmp/phone-failed').stdout}")
            time.sleep(1)
        else:
            raise RuntimeError(f"{c}: screen and sound never ready")
    pin_neighbours((SRV, ALICE, BOB))


def teardown():
    sh(["docker", "rm", "-f", SRV, ALICE, BOB])
    sh(["docker", "network", "rm", NET])


def wait_for(c, path, needle, seconds):
    for _ in range(seconds):
        if dx(c, "grep", "-q", needle, path, timeout=10).returncode == 0:
            return True
        time.sleep(1)
    return False


def run_profile(name):
    if name != "none" and PROFILES.get(name, (0, 0, 0, False))[3]:
        raise RuntimeError(f"{name} needs the internal network, not built yet")
    d = f"/out/{name}"
    host_d = os.path.join(outroot, name)
    clear_shaping((SRV, ALICE, BOB))
    if name != "none":
        rate, rtt, loss, _internal = PROFILES[name] if name != "P0" else (0, 0, 100, False)
        for c in (SRV, ALICE, BOB):
            netem(c, rate, rtt / 2, loss)
        if name == "P4":
            start_duty_loop((SRV, ALICE, BOB), rate, rtt, loss)
    port = start_server(SRV, name)
    url = f"http://{ip_of(SRV)}:{port}"
    stop = f"{d}/alice.done"
    for c in (ALICE, BOB):
        dx(c, "sh", "-c", f"rm -rf /tmp/state; mkdir -p /tmp/state {d}")
    dx(BOB, "rm", "-f", f"{d}/bob.exit", stop)

    sh(["docker", "exec", "-d", BOB, "sh", "-c",
        f"/app/tremulator --lab --server {url} --name bob --state /tmp/state --out {d}/bob.jsonl "
        f"--audio --until-file {stop} > {d}/bob.stdout 2>&1; echo $? > {d}/bob.exit"])
    if not wait_for(BOB, f"{d}/bob.jsonl", "waiting-for-call", 90):
        raise RuntimeError("bob never got to waiting-for-call")

    # Both screens are recorded from before the call to after it: Bob's is
    # what arrived, Alice's what was sent, so a freeze on Bob's alone is the
    # link's. The start time is written in the container just before ffmpeg
    # starts, so freezes can be placed against each phone's own connected
    # and ended times (same clock: the containers share the host's).
    rec_s = call_s + 60
    for c, who in ((BOB, "bob"), (ALICE, "alice")):
        sh(["docker", "exec", "-d", c, "sh", "-c",
            f"date -u +%Y-%m-%dT%H:%M:%S.%NZ > {d}/{who}_record.start; exec ffmpeg -y -loglevel error "
            f"-f x11grab -framerate 30 -video_size 1280x720 -i :0 -t {rec_s} -c:v libx264 "
            f"-preset ultrafast -crf 30 -pix_fmt yuv420p {d}/{who}_screen.mp4 > {d}/{who}_record.log 2>&1"])
    # The test pattern is up and moving before Alice's app starts; once her
    # app's window exists the pattern is raised above it (no window manager:
    # a new window maps on top). calls2 started the pattern 3 s after the
    # app, and Bob received 2.15 s of her still app window as a "freeze".
    # Ubuntu 24.04's xdotool has windowraise but not windowlower (calls3).
    sh(["docker", "exec", "-d", ALICE, "sh", "-c",
        "ffplay -loglevel error -noborder -left 0 -top 0 -x 1280 -y 720 -an "
        "-f lavfi 'testsrc2=size=1280x720:rate=30' > /tmp/ffplay.log 2>&1"])
    time.sleep(2)
    t0 = time.time()
    sh(["docker", "exec", "-d", ALICE, "sh", "-c",
        f"/app/tremulator --lab --server {url} --name alice --state /tmp/state --out {d}/alice.jsonl "
        f"--peer bob --video --audio --call-s {call_s} > {d}/alice.stdout 2>&1; echo $? > {d}/alice.exit"])
    raised = False
    for _ in range(40):
        if dx(ALICE, "xdotool", "search", "--name", "^tremulator$", timeout=10).returncode == 0:
            raised = dx(ALICE, "xdotool", "search", "--class", "ffplay", "windowraise",
                        timeout=10).returncode == 0
            break
        time.sleep(0.25)
    for _ in range(call_s + 240):
        if dx(ALICE, "test", "-e", f"{d}/alice.exit", timeout=10).returncode == 0:
            break
        time.sleep(1)
    alice_s = round(time.time() - t0, 1)
    dx(ALICE, "sh", "-c", "pkill -x ffplay; true")
    for _ in range(rec_s + 30):
        if dx(ALICE, "pgrep", "-x", "ffmpeg", timeout=10).returncode != 0:
            break
        time.sleep(1)
    time.sleep(5)
    dx(BOB, "touch", stop)
    for _ in range(120):
        if dx(BOB, "test", "-e", f"{d}/bob.exit", timeout=10).returncode == 0:
            break
        time.sleep(1)
    # let the recording reach its end and close the file
    for _ in range(rec_s + 30):
        if dx(BOB, "pgrep", "-x", "ffmpeg", timeout=10).returncode != 0:
            break
        time.sleep(1)
    stop_server(SRV, name)
    clear_shaping((SRV, ALICE, BOB))

    rec = {"profile": name, "alice_wall_s": alice_s, "pattern_raised": raised,
           "alice_exit": read(ALICE, f"{d}/alice.exit"), "bob_exit": read(BOB, f"{d}/bob.exit")}
    for line in sh(["python3", "-I", SUMMARY, os.path.join(host_d, "alice.jsonl"),
                    os.path.join(host_d, "bob.jsonl")]).stdout.splitlines():
        s = json.loads(line)
        who = "alice" if s["log"].endswith("alice.jsonl") else "bob"
        rec[who] = {k: v for k, v in s.items() if k != "log"}
    rec["recording_bob"] = recording_facts(host_d, "bob")
    rec["recording_alice"] = recording_facts(host_d, "alice")
    rec.update(fingerprint_hunt(host_d))
    log(rec)


def read(c, path):
    return dx(c, "cat", path, timeout=10).stdout.strip() or None


def recording_facts(host_d, who):
    """Frozen video on one phone's screen during the call, by ffmpeg
    freezedetect (the Gate 1 instrument), between that phone's connected and
    call-ended lines; plus three stills from the call to look at."""
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
    end = next((e for e in events if e["event"] == "call-ended"), None)
    if conn is None or end is None:
        return {"length_s": length, "call_window": None}
    a, b = utc(conn["t"]) - rec_start, utc(end["t"]) - rec_start
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


if __name__ == "__main__":
    if "--skip-build" not in sys.argv:
        build()
    log({"event": "start", "profiles": profiles, "call_s": call_s})
    try:
        setup()
        for name in profiles:
            run_profile(name)
    finally:
        teardown()
        log({"event": "end"})
