#!/usr/bin/env python3
"""The voice-delay instrument across two containers, under a known
condition: the same click played at the same wall-clock moment into Alice's
microphone and Bob's speaker must get the same times.

    python3 lab/gate2/cross_stamp_check.py [--trials 8]

pulse_stamp_check.py proved two recordings in ONE container agree (0 ms, 8
of 8); a call compares recordings in two containers. Here two phone
containers record as calls.py does (voice_delay.record_cmd: Alice's
mic.monitor, Bob's speaker.monitor); each then sleeps until one shared wall
time T (the containers share the host's clock) and plays the click track
into its own sink. Alice's click time minus Bob's is the instrument's
cross-container error plus the difference in the two players' start-up,
which is the same program on the same image, so it should read near 0.
calls9 `none` read 103 ms and `plus500` 847 ms one way, 744 ms more for
500 ms added: this check says how much of that is the instrument.

One line per trial in results/cross-stamp-check.jsonl, flushed. Starts and
removes two containers on the default bridge network; no network created.
Do not start without Grey's go (docs/GATE1.md).
"""
import json
import os
import sys
import time

from labkit import dx, sh
from voice_delay import click_track_cmd, onsets, record_cmd, start_time, to_wav

HERE = os.path.dirname(os.path.abspath(__file__))
PHONE_IMG = "tremulator-g2-calls:latest"
OUT = os.path.join(HERE, "results", "cross-stamp-check")
SIDES = {"g2c-xalice": ("mic", "alice_sent"), "g2c-xbob": ("speaker", "bob_heard")}
trials = int(sys.argv[sys.argv.index("--trials") + 1]) if "--trials" in sys.argv else 8


def main():
    os.makedirs(OUT, exist_ok=True)
    summary = open(os.path.join(HERE, "results", "cross-stamp-check.jsonl"), "a")
    for c in SIDES:
        sh(["docker", "rm", "-f", c])
        sh(["docker", "run", "-d", "--rm", "--name", c, "-v", f"{OUT}:/out", PHONE_IMG], check=True)
    try:
        for c in SIDES:
            for _ in range(60):
                if dx(c, "test", "-e", "/tmp/phone-ready", timeout=10).returncode == 0:
                    break
                time.sleep(1)
            else:
                raise RuntimeError(f"{c} never ready")
            dx(c, "sh", "-c", " ".join(click_track_cmd("/tmp/click.wav", 3)))
        for i in range(trials):
            for f in os.listdir(OUT):
                os.remove(os.path.join(OUT, f))
            for c, (sink, stem) in SIDES.items():
                sh(["docker", "exec", "-d", c, "sh", "-c", record_cmd(f"{sink}.monitor", f"/out/{stem}", 60)])
            # Recordings start a varied 0.5-2.6 s before the shared moment.
            t = time.time() + 2 + 0.3 * (i % 8)
            for c, (sink, _) in SIDES.items():
                sh(["docker", "exec", "-d", c, "sh", "-c",
                    f"d=$(awk -v t={t:.6f} -v n=$(date +%s.%N) 'BEGIN{{print t-n}}'); "
                    f"sleep $d; paplay --device={sink} /tmp/click.wav"])
            time.sleep(t - time.time() + 26)
            for c in SIDES:
                dx(c, "sh", "-c", "pkill -INT -x ffmpeg; true")
            for c in SIDES:
                for _ in range(30):
                    if dx(c, "pgrep", "-x", "ffmpeg", timeout=10).returncode != 0:
                        break
                    time.sleep(0.5)
                dx(c, "chown", "-R", f"{os.getuid()}:{os.getgid()}", "/out", user="0")
            got = {}
            for _, (_, stem) in SIDES.items():
                mkv = os.path.join(OUT, f"{stem}.mkv")
                t0 = start_time(mkv)
                got[stem] = [t0 + x for x in onsets(to_wav(mkv))]
            a, b = got["alice_sent"], got["bob_heard"]
            n = min(len(a), len(b))
            rec = {"trial": i, "onsets_alice": len(a), "onsets_bob": len(b),
                   "alice_minus_bob_ms": [round((a[k] - b[k]) * 1000) for k in range(n)],
                   "alice_minus_scheduled_ms": [round((a[k] - t - 5 - 10 * k) * 1000) for k in range(len(a))]}
            summary.write(json.dumps(rec) + "\n")
            summary.flush()
            print(json.dumps(rec), flush=True)
    finally:
        for c in SIDES:
            sh(["docker", "rm", "-f", c])


if __name__ == "__main__":
    main()
