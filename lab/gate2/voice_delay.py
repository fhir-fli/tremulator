#!/usr/bin/env python3
"""One-way voice delay from two recordings on one clock: what went into the
sender's microphone and what came out of the receiver's speaker.

    voice_delay.py SENT.mkv RECEIVED.mkv OUT.jsonl     a call's two recordings
    voice_delay.py --self-check DIR                    the instrument, offline

Each recording is made in its container by ffmpeg's PulseAudio input, which
stamps the first sample with the wall clock (its `wallclock` option, on by
default); the containers share the host's clock. Onsets come from Gate 1's
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


def start_time(path):
    """The wall-clock time of the first sample, from the container's ffmpeg."""
    return float(sh(["ffprobe", "-v", "error", "-show_entries", "format=start_time",
                     "-of", "csv=p=0", path]).strip())


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
    # ffmpeg drops the wall-clock stamp without -copyts and starts at 0.
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
    return {"clicks_sent": len(sent_on), "clicks_heard": len(delays),
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
    # The same recording twice, stamped T and T + 0.300 s with T a wall-clock
    # time: what the container's ffmpeg stamp does.
    t = 1_800_000_000
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", track, "-output_ts_offset", str(t), sent])
    # Clicks 3, 6, 9 (at 25, 55, 85 s) silenced in the heard copy.
    mute = "+".join(f"between(t,{10 * k - 5 - 0.1},{10 * k - 5 + 0.2})" for k in (3, 6, 9))
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", track, "-af", f"volume=enable='{mute}':volume=0",
        "-output_ts_offset", str(t + 0.3), heard])
    got = measure(sent, heard, os.path.join(d, "pairs.jsonl"))
    want = {"clicks_sent": 9, "clicks_heard": 6, "delay_median_ms": 300}
    ok = all(got[k] == v for k, v in want.items()) and got["delay_min_ms"] == got["delay_max_ms"] == 300
    print(json.dumps({"self_check": "pass" if ok else "FAIL", "got": got, "want": want}), flush=True)
    return ok


if __name__ == "__main__":
    if sys.argv[1:2] == ["--self-check"]:
        sys.exit(0 if self_check(sys.argv[2]) else 1)
    print(json.dumps(measure(*sys.argv[1:4])), flush=True)
