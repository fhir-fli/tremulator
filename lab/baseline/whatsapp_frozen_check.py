#!/usr/bin/env python3
"""Recompute WhatsApp's frozen-video seconds per minute (GATE1.md table) from
the committed freeze files, to check the reference numbers. The recording's
start is its file time (written at the end) less its duration; the call
window is the driver's call_tap to hangup. Each minute of the window is
reported, then the whole-window rate.

    cd lab/baseline && python3 whatsapp_frozen_check.py

Two readings per call: the committed freeze file (its crop, if any, is not
recorded), and a fresh freezedetect cropped to the remote video only
(CROP: x 0-360, y 60-1040 of the 494x1080 recording, which leaves out the
status bar with its clock, the self-view in the lower right from x 365, and
the navigation bar; chosen from stills at 300 s (P1), 120 s (P2) and 1560 s (P3; its clock
reads 11:11, rule gives 11:11:10)). The
start-time rule is checked by the status-bar clock: P1's still at 300 s
reads 10:36, start + 300 s = 10:36:29.
"""
CROP = "crop=360:980:0:60,freezedetect=n=-60dB:d=0.5"
import json, os, re, subprocess
from datetime import datetime
R = "results"
CASES = [("P1", "p1-video2.mkv", "p1-video2.freeze.txt", "android_p1video2_call.jsonl", "android_p1video2_hangup.jsonl"),
         ("P2", "p2-video.mkv", "p2-video.freeze.txt", "android_p2video_call.jsonl", "android_p2video_hangup.jsonl"),
         ("P3", "p3.mkv", "p3.freeze.txt", "android_p3video_call.jsonl", "android_p3video_hangup.jsonl")]
def first_t(f):
    return datetime.fromisoformat(json.loads(open(os.path.join(R, f)).readline())["t"]).timestamp()
def spans(txt):
    s = None; out = []
    for l in open(os.path.join(R, txt)):
        m = re.search(r"freeze_start: ([\d.]+)", l)
        if m: s = float(m.group(1))
        m = re.search(r"freeze_end: ([\d.]+)", l)
        if m and s is not None: out.append((s, float(m.group(1)))); s = None
    return out, s
def overlap(sp, a, b):
    return sum(max(0, min(e, b) - max(s, a)) for s, e in sp)
def report(prof, label, txt, start, dur, a, b):
    sp, open_s = spans(txt)
    if open_s is not None: sp.append((open_s, dur))
    mins = []
    t = a
    while t < b - 1:
        e = min(t + 60, b); mins.append(round(overlap(sp, t, e) / (e - t) * 60, 1)); t = e
    print(prof, label, f"| window {a:.1f}-{b:.1f} s ({b-a:.0f} s) | per minute", mins,
          "| whole", round(overlap(sp, a, b) / (b - a) * 60, 2), flush=True)

for prof, mkv, txt, call, hang in CASES:
    p = os.path.join(R, mkv)
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p],
                               capture_output=True, text=True).stdout)
    start = os.path.getmtime(p) - dur
    a, b = first_t(call) - start, first_t(hang) - start
    cropped = txt.replace(".freeze.txt", ".cropped.freeze.txt")
    if not os.path.exists(os.path.join(R, cropped)):
        with open(os.path.join(R, cropped), "w") as f:
            subprocess.run(["ffmpeg", "-hide_banner", "-nostats", "-i", p, "-vf", CROP, "-map", "0:v", "-f", "null", "-"],
                           stderr=f, check=True)
    for label, fname in (("committed file", txt), ("cropped to remote video", cropped)):
        report(prof, label, fname, start, dur, a, b)
