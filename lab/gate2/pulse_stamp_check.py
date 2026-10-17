#!/usr/bin/env python3
"""The voice-delay instrument under a known condition: the same sound,
recorded twice in one container, must get the same wall-clock times.

    python3 lab/gate2/pulse_stamp_check.py [--trials 8]

calls9-before (2026-10-17) read Bob hearing Alice's clicks 0.27-0.46 s BEFORE
she sent them on two of three calls, which cannot happen, so the start stamp
ffmpeg's PulseAudio input gives a recording (voice_delay.start_time) is
suspect. Measured: the old stamp, 8 trials, -273 to -722 ms; with a 10 ms
buffer, 8 trials, -60 to -719 ms (results/pulse-stamp-check.out). Here one phone container records its microphone's monitor twice,
the second recording starting a varied 0.3-2.9 s after the first, exactly as
calls.py starts them (same ffmpeg command), then a click track plays into the
microphone. Each click's wall-clock time from recording A minus that from
recording B is the stamp error between two recordings; true value 0.

One line per trial in results/pulse-stamp-check.jsonl, flushed. Starts and
removes one container (`g2c-stampcheck`) on the default bridge network, no
network created. Do not start without Grey's go (docs/GATE1.md).
"""
import json
import os
import statistics
import sys
import time

from labkit import dx, sh
from voice_delay import click_track_cmd, onsets, record_cmd, start_time, to_wav

HERE = os.path.dirname(os.path.abspath(__file__))
PHONE_IMG = "tremulator-g2-calls:latest"
NAME = "g2c-stampcheck"
OUT = os.path.join(HERE, "results", "pulse-stamp-check")
trials = int(sys.argv[sys.argv.index("--trials") + 1]) if "--trials" in sys.argv else 8


def record(who, seconds):
    # calls.py's own command (voice_delay.record_cmd).
    sh(["docker", "exec", "-d", NAME, "sh", "-c", record_cmd("mic.monitor", f"/out/{who}", seconds)])


def main():
    os.makedirs(OUT, exist_ok=True)
    summary = open(os.path.join(HERE, "results", "pulse-stamp-check.jsonl"), "a")
    sh(["docker", "rm", "-f", NAME])
    sh(["docker", "run", "-d", "--rm", "--name", NAME, "-v", f"{OUT}:/out", PHONE_IMG], check=True)
    try:
        for _ in range(60):
            if dx(NAME, "test", "-e", "/tmp/phone-ready", timeout=10).returncode == 0:
                break
            time.sleep(1)
        else:
            raise RuntimeError("phone never ready")
        dx(NAME, "sh", "-c", " ".join(click_track_cmd("/tmp/click.wav", 3)))
        for i in range(trials):
            gap = 0.3 + (2.6 * i / max(1, trials - 1))
            for f in os.listdir(OUT):
                os.remove(os.path.join(OUT, f))
            record("a", 45)
            time.sleep(gap)
            record("b", 45)
            time.sleep(1)
            dx(NAME, "paplay", "--device=mic", "/tmp/click.wav", timeout=60)
            dx(NAME, "sh", "-c", "pkill -INT -x ffmpeg; true")
            for _ in range(30):
                if dx(NAME, "pgrep", "-x", "ffmpeg", timeout=10).returncode != 0:
                    break
                time.sleep(0.5)
            dx(NAME, "chown", "-R", f"{os.getuid()}:{os.getgid()}", "/out", user="0")
            got = {}
            for who in ("a", "b"):
                mkv = os.path.join(OUT, f"{who}.mkv")
                t0 = start_time(mkv)
                got[who] = [t0 + t for t in onsets(to_wav(mkv))]
            n = min(len(got["a"]), len(got["b"]))
            diffs = [round((got["a"][k] - got["b"][k]) * 1000) for k in range(n)]
            rec = {"instrument": "packet-arrival", "trial": i, "gap_s": round(gap, 2), "onsets_a": len(got["a"]),
                   "onsets_b": len(got["b"]), "a_minus_b_ms": diffs}
            summary.write(json.dumps(rec) + "\n")
            summary.flush()
            print(json.dumps(rec), flush=True)
    finally:
        sh(["docker", "rm", "-f", NAME])


if __name__ == "__main__":
    main()
