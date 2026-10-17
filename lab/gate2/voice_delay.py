#!/usr/bin/env python3
"""One-way voice delay from two recordings on one clock: what went into the
sender's microphone and what came out of the receiver's speaker.

    voice_delay.py SENT.mkv RECEIVED.mkv OUT.jsonl     a call's two recordings
    voice_delay.py --self-check DIR                    the instrument, offline

Each recording is made in its container by ffmpeg's PulseAudio input
(record_cmd) with every 10 ms packet stamped with its arrival on the wall
clock (`-use_wallclock_as_timestamps 1`) and listed in the recording's log
(<recording>_record.log, ashowinfo lines); the containers share the host's
clock. The recording's start is the earliest of (arrival - audio before the
packet): a packet can arrive late, never early, so the earliest bounds the
true start most tightly. The start stamp ffmpeg prints by default was wrong
by 60-722 ms, varying per recording (pulse_stamp_check.py, 2026-10-17, two
recordings of one sound in one container: 16 of 16 trials). Onsets come from Gate 1's
amplitude detector (lab/tool/bin/baseline_onsets.dart, threshold 0.5 of the
file's peak, 150 ms dead time), so the instrument is the one that measured
WhatsApp. Each click sent is paired with the first click heard within 3 s
after it; a click with none is counted as lost.

A received file whose peak is under 1,000 of 32,767 is reported as silent and
yields no pairs: on near-silence the detector's 0.5-of-peak level falls into
the noise and would pair noise with clicks.

The self-check makes a click track, a copy delayed by a known 0.300 s and a
copy with every third click removed, and must read back 300 ms and the loss
count; it is the known condition the instrument is tested under first.
"""
import json
import os
import re
import statistics
import subprocess
import sys
import wave
from array import array

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.abspath(os.path.join(HERE, "..", "tool"))
SILENT_PEAK = 1000
PAIR_WINDOW_S = 3.0


def sh(cmd, **kw):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=600, **kw)
    if r.returncode != 0:
        raise RuntimeError(f"{' '.join(cmd)}: {r.stderr.strip()}")
    return r.stdout


def click_track_cmd(path, clicks):
    """sox: a 30 ms 1 kHz tone 5 s into every 10 s, `clicks` times (Gate 1:
    10 s of silence around each clap)."""
    return ["sox", "-n", "-r", "48000", "-c", "1", "-b", "16", path,
            "synth", "0.03", "sine", "1000", "vol", "0.8", "pad", "5", "4.97", "repeat", str(clicks - 1)]


FRAGMENT_BYTES = 1920  # 10 ms of 48 kHz stereo 16-bit, the pulse default format
FRAME = re.compile(r"Parsed_ashowinfo_\d+ @ \S+\] n:(\d+) pts:(-?\d+) .*? rate:(\d+) nb_samples:(\d+)")


def record_cmd(source, stem, cap_s):
    """The shell command recording PulseAudio `source` to <stem>.mkv with
    each packet's arrival logged to <stem>_record.log. No -t: with -copyts
    (which keeps the arrival stamps) -t counts from 0 and the file came out
    empty (calls6), so `timeout -s INT` is the cap and the caller stops it
    with SIGINT. ashowinfo's pts is in units of 1/rate (its first value
    divided by 48000 equals ffmpeg's printed start, checked 2026-10-17)."""
    return (f"exec timeout -s INT {cap_s} ffmpeg -y -nostdin -hide_banner -nostats "
            f"-use_wallclock_as_timestamps 1 -f pulse -fragment_size {FRAGMENT_BYTES} -i {source} "
            f"-copyts -af ashowinfo -ac 1 -c:a pcm_s16le {stem}.mkv > {stem}_record.log 2>&1")


def start_time(path):
    """The wall-clock time of the recording's first sample: the earliest
    (packet arrival - audio before that packet) over the packets in
    <recording>_record.log."""
    log = os.path.splitext(path)[0] + "_record.log"
    best, before = None, 0
    with open(log, errors="replace") as f:
        for line in f:
            m = FRAME.search(line)
            if m is None:
                continue
            _, pts, rate, samples = (int(g) for g in m.groups())
            t = (pts - before) / rate
            best = t if best is None else min(best, t)
            before += samples
    if best is None:
        raise RuntimeError(f"{os.path.basename(log)}: no packet times (ashowinfo lines)")
    return best


def to_wav(path):
    wav = os.path.splitext(path)[0] + ".wav"
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", "48000",
        "-c:a", "pcm_s16le", wav])
    return wav


def peak(wav):
    with wave.open(wav) as w:
        a = array("h", w.readframes(w.getnframes()))
    return max((abs(s) for s in a), default=0)


def onsets(wav):
    out = sh(["dart", "run", "bin/baseline_onsets.dart", os.path.abspath(wav)], cwd=TOOL)
    return [float(m.group(1)) for m in re.finditer(r"^\s+([\d.]+) s", out, re.M)]


def pair(sent, heard):
    """(sent time, delay or None) for every click sent."""
    out = []
    for s in sent:
        r = next((h for h in heard if s < h <= s + PAIR_WINDOW_S), None)
        out.append((s, None if r is None else r - s))
    return out


def measure(sent_path, heard_path, out_path):
    sent_wav, heard_wav = to_wav(sent_path), to_wav(heard_path)
    t_sent, t_heard = start_time(sent_path), start_time(heard_path)
    # A stamp that is not a wall-clock time means the instrument is broken.
    for path, t in ((sent_path, t_sent), (heard_path, t_heard)):
        if t < 1e9:
            raise RuntimeError(f"{os.path.basename(path)} starts at {t}: no wall-clock stamp")
    heard_peak = peak(heard_wav)
    sent_on = [t_sent + t for t in onsets(sent_wav)]
    heard_on = [] if heard_peak < SILENT_PEAK else [t_heard + t for t in onsets(heard_wav)]
    pairs = pair(sent_on, heard_on)
    with open(out_path, "w") as f:
        for s, d in pairs:
            f.write(json.dumps({"sent": round(s, 4), "delay_ms": None if d is None else round(d * 1000)}) + "\n")
            f.flush()
    delays = sorted(d * 1000 for _, d in pairs if d is not None)
    return {"sent_start": round(t_sent, 4), "heard_start": round(t_heard, 4),
            "clicks_sent": len(sent_on), "clicks_heard": len(delays),
            "heard_peak": heard_peak, "heard_onsets": len(heard_on),
            "delay_median_ms": round(statistics.median(delays)) if delays else None,
            "delay_min_ms": round(delays[0]) if delays else None,
            "delay_max_ms": round(delays[-1]) if delays else None}


def self_check(d):
    """Known condition: a 0.300 s delay and 3 of 9 clicks removed."""
    os.makedirs(d, exist_ok=True)
    track = os.path.join(d, "track.wav")
    sh(click_track_cmd(track, 9))
    sent = os.path.join(d, "sent.mkv")
    heard = os.path.join(d, "heard.mkv")
    # The same recording twice, logged as starting at T and T + 0.300 s with
    # T a wall-clock time, as ffmpeg's ashowinfo lists packets: 480 samples
    # each, every one arriving 2-40 ms late except one 2 ms late, so the
    # start must come out exactly 2 ms after T (and after T + 0.3).
    t = 1_800_000_000
    def logged(path, start):
        with open(os.path.splitext(path)[0] + "_record.log", "w") as f:
            for k in range(9000):
                late = 0.002 if k == 4000 else 0.002 + 0.038 * ((k * 7919) % 97) / 96 + 0.001
                pts = round((start + (k + 1) * 0.01 - 0.01 + late) * 48000)
                f.write(f"[Parsed_ashowinfo_0 @ 0x5] n:{k} pts:{pts} pts_time:1.8e+09 fmt:s16 "
                        f"channels:2 chlayout:stereo rate:48000 nb_samples:480 checksum:0\n")
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", track, sent])
    logged(sent, t)
    # Clicks 3, 6, 9 (at 25, 55, 85 s) silenced in the heard copy.
    mute = "+".join(f"between(t,{10 * k - 5 - 0.1},{10 * k - 5 + 0.2})" for k in (3, 6, 9))
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", track, "-af", f"volume=enable='{mute}':volume=0", heard])
    logged(heard, t + 0.3)
    starts_ok = (abs(start_time(sent) - (t + 0.002)) < 1e-4
                 and abs(start_time(heard) - (t + 0.302)) < 1e-4)
    got = measure(sent, heard, os.path.join(d, "pairs.jsonl"))
    want = {"clicks_sent": 9, "clicks_heard": 6, "delay_median_ms": 300}
    ok = (starts_ok and all(got[k] == v for k, v in want.items())
          and got["delay_min_ms"] == got["delay_max_ms"] == 300)
    print(json.dumps({"self_check": "pass" if ok else "FAIL", "got": got, "want": want}), flush=True)
    return ok


if __name__ == "__main__":
    if sys.argv[1:2] == ["--self-check"]:
        sys.exit(0 if self_check(sys.argv[2]) else 1)
    print(json.dumps(measure(*sys.argv[1:4])), flush=True)
