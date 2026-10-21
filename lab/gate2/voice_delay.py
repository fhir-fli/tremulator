#!/usr/bin/env python3
"""One-way voice delay from two recordings on one clock: what went into the
sender's microphone and what came out of the receiver's speaker.

    voice_delay.py SENT.mkv RECEIVED.mkv OUT.jsonl     a call's two recordings
    voice_delay.py --self-check DIR                    the instrument, offline
    voice_delay.py --self-check-speech DIR             the same, with speech

With speech (E7, `call_track`): the same clicks with real speech between
them, so the call carries the load of a person talking. The speech is ITU-T
P.501 (07/2026) clause 7.3.2, the British English single-talk sequence
(speech/, with ITU's notice), looped, at half its level, stopping 1 s before
each click and resuming 1 s after it.

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
WhatsApp.

Each click is one 30 ms beep whose pitch is its number modulo 6
(CODE_TONES, call_track). Both recordings are band-passed around each tone
in turn and onsets found in each, so a click heard is known by its number.
A heard beep counts only where its band reaches CLICK_FRACTION of the sent
beep's peak in that band (coded):
the self-check's band with its clicks removed peaked at 0.28 (the next
tones leaking through) and speech alone at 0.10; calls241fc's heard sound
(the 1 kHz track) at 0.31 of a beep in the top bands, and its beep arrived
at 1.17 of the level sent. Heard beeps paired with no click are counted
(heard_unpaired): noise taken for beeps shows there. Each click sent is paired with the
first click heard after it, within PAIR_WINDOW_S, carrying the same tone,
and later than the last one paired (a call's sound plays in order); a click
with none is counted as lost.

Why tones: until calls23 every click was the same 1 kHz beep, paired with the
first click heard within 3 s after it, so a click 10-13 s late read as the
next click on time (calls23a: 8 ms, with a 15 s round trip) and one later
than 3 s counted as lost. Two beeps a gap apart (13036c9) carried the number
but any lost beep lost the click: calls241fc P1 (5% loss at each phone), 8
of 29 clicks unread, each a lone beep with its partner gone; one beep a
click keeps the loss exposure Gate 1's single clap had. The beeps of
pulse_stamp_check.py and cross_stamp_check.py (click_track_cmd) stay single
1 kHz: they time one recording against another, not a call.

A received file whose peak is under 1,000 of 32,767 is reported as silent and
yields no pairs: on near-silence the detector's 0.5-of-peak level falls into
the noise and would pair noise with clicks.

The self-check makes a click track, a copy delayed by a known 0.300 s and a
copy with every third click removed, and must read back 300 ms and the loss
count; it is the known condition the instrument is tested under first.
"""
import json
import math
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
# Click n's pitch is CODE_TONES[n % 6]: about 1.35 apart, so through
# another tone's band (Q 8) a beep is at most about 0.2 of its own band's
# peak, under the detector's 0.5; within Opus wideband's 8 kHz.
CODE_TONES = [800, 1100, 1500, 2000, 2700, 3600]
BEEP_S = 0.03
# Under the 60 s after which the codes repeat.
PAIR_WINDOW_S = 50.0
SPEECH = os.path.join(HERE, "speech", "P501_7.3.2_FB_male_female_single-talk_seq.wav")
SPEECH_GAIN = 0.5
SPEECH_GAP_S = 1.0  # quiet either side of each click
BAND = "bandpass=f={}:t=q:w=8"
# A heard onset counts as a beep only if (calls26, all 18 runs, e7_surround.py:
# 480 paired onsets and 88 not, results/calls26-surround.jsonl):
# - its band reaches CLICK_FRACTION of the sent beep's peak in that band.
#   0.5 (9a31ce1) dropped real beeps the codec left at 0.36-0.46, whole
#   pitches at a time in some calls (1100 Hz in calls262fd P1-blocked);
# - the whole recording is quiet around it, at most QUIET_FRACTION of the
#   beep's own peak over QUIET_WINDOWS (s from the onset), as the track
#   keeps SPEECH_GAP_S clear either side: 66 of the 88 unpaired onsets had
#   sound there and 11 of 480 paired ones did, those mostly paired 2-27 s
#   off the call's median, so strays themselves. Over 0.8 s it dropped 13
#   more real beeps, where the receiver had sped playback up through the
#   quiet; over 0.3 s it kept 2 more;
# - no other band's onset within BEEP_S of it is stronger, against its own
#   band's sent peak: the leak of a real beep into a neighbouring band came
#   at 0.25-0.37 at the same instant (calls262dd, calls263dd).
# With all three, every one of the 18 runs had no unpaired onset, and 468
# of 522 clicks paired against 459 under the half-level rule. The rule was
# fitted to those runs; the self-check holds each case as a known condition.
CLICK_FRACTION = 0.25
QUIET_FRACTION = 0.1
QUIET_WINDOWS = ((-0.5, -0.15), (0.2, 0.5))


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


def call_track(path, clicks, speech=False):
    """The call's sound: click n 5 s into its 10 s, a 30 ms tone of
    CODE_TONES[n % 6] at 0.8 of full scale; with
    `speech`, SPEECH looped in between at SPEECH_GAIN, SPEECH_GAP_S clear of
    each click. 48 kHz mono 16-bit."""
    rate = 48000
    talk = None
    if speech:
        with wave.open(SPEECH) as w:
            if (w.getframerate(), w.getnchannels(), w.getsampwidth()) != (48000, 1, 2):
                raise RuntimeError(f"{SPEECH}: not 48 kHz mono 16-bit")
            talk = array("h", w.readframes(w.getnframes()))
    out = array("h", bytes(2 * clicks * 10 * rate))
    k = 0
    for c in range(clicks):
        base = c * 10 * rate
        if talk is not None:
            for a, b in ((0, 5 - SPEECH_GAP_S), (5 + SPEECH_GAP_S, 10)):
                for i in range(base + int(a * rate), base + int(b * rate)):
                    out[i] = int(talk[k % len(talk)] * SPEECH_GAIN)
                    k += 1
        tone = CODE_TONES[c % len(CODE_TONES)]
        for i in range(int(BEEP_S * rate)):
            out[base + 5 * rate + i] = int(0.8 * 32767 * math.sin(2 * math.pi * tone * i / rate))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(out.tobytes())


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


def to_wav(path, band=None):
    """`path` as 48 kHz mono 16-bit WAV, band-passed around `band` Hz if set."""
    wav = os.path.splitext(path)[0] + (f"_band{band}.wav" if band else ".wav")
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", path, "-ac", "1", "-ar", "48000",
        *(["-af", BAND.format(band)] if band else []), "-c:a", "pcm_s16le", wav])
    return wav


def peak(wav):
    with wave.open(wav) as w:
        a = array("h", w.readframes(w.getnframes()))
    return max((abs(s) for s in a), default=0)


def onsets(wav, threshold=0.5):
    """Onset times (s) in `wav`: where it first passes `threshold` of its own
    peak, at least 150 ms after the last (baseline.dart onsets)."""
    out = sh(["dart", "run", "bin/baseline_onsets.dart", os.path.abspath(wav),
              "--threshold", repr(threshold)], cwd=TOOL)
    return [float(m.group(1)) for m in re.finditer(r"^\s+([\d.]+) s", out, re.M)]


def level_at(wav, t, span=BEEP_S + 0.02):
    """The peak of `wav` over `span` seconds from `t`."""
    with wave.open(wav) as w:
        w.setpos(max(0, min(w.getnframes(), int(t * w.getframerate()))))
        a = array("h", w.readframes(int(span * w.getframerate())))
    return max((abs(x) for x in a), default=0)


def coded(path, start, sent_peaks=None):
    """(time, code) for every beep in the recording at `path`, in time order,
    from its onsets in each tone's band, by the rule above CLICK_FRACTION;
    and each band's peak. The levels are fractions of `sent_peaks` (each
    band's peak in the sent recording) or, for the sent recording itself,
    of its own peaks. Both sides use the same bar so a beep at full level
    is timed at the same point of its rise on each (one 2 ms apart when
    the sent side kept the detector's half-peak bar)."""
    full = to_wav(path)
    bands = [to_wav(path, tone) for tone in CODE_TONES]
    peaks = [peak(wav) for wav in bands]
    ref = sent_peaks or peaks
    found = []
    for code, wav in enumerate(bands):
        # The detector's own bar is half the band's peak in this recording,
        # so a beep at a third of a louder one in its band was never an
        # onset (the self-check's click 2).
        for t in onsets(wav, min(1.0, CLICK_FRACTION * ref[code] / max(peaks[code], 1))):
            level = level_at(wav, t)
            if level < max(SILENT_PEAK, CLICK_FRACTION * ref[code]):
                continue
            beep = level_at(full, t)
            around = max(level_at(full, t + a, b - a) for a, b in QUIET_WINDOWS)
            if around <= QUIET_FRACTION * max(beep, 1):
                found.append((t, code, level / ref[code]))
    kept = [(t, code) for t, code, f in found
            if not any(abs(t2 - t) <= BEEP_S and f2 > f for t2, _, f2 in found)]
    return sorted((start + t, code) for t, code in kept), peaks


def pair(sent, heard):
    """(sent time, delay or None) for every click sent: sent and heard are
    (time, code), in time order."""
    out, after = [], 0
    for s, code in sent:
        hit = next((j for j in range(after, len(heard))
                    if heard[j][1] == code and s < heard[j][0] <= s + PAIR_WINDOW_S), None)
        if hit is None:
            out.append((s, None))
        else:
            out.append((s, heard[hit][0] - s))
            after = hit + 1
    return out


def measure(sent_path, heard_path, out_path, speech=False):
    """`speech` is recorded in the result; the bands do the same work with
    or without it."""
    t_sent, t_heard = start_time(sent_path), start_time(heard_path)
    # A stamp that is not a wall-clock time means the instrument is broken.
    for path, t in ((sent_path, t_sent), (heard_path, t_heard)):
        if t < 1e9:
            raise RuntimeError(f"{os.path.basename(path)} starts at {t}: no wall-clock stamp")
    heard_peak = peak(to_wav(heard_path))
    sent_on, sent_peaks = coded(sent_path, t_sent)
    want = [c % len(CODE_TONES) for c in range(len(sent_on))]
    if [c for _, c in sent_on] != want:
        # What went into the microphone must read back as the track made.
        raise RuntimeError(f"{os.path.basename(sent_path)}: codes {[c for _, c in sent_on]}: "
                           "not a coded click track")
    heard_on, _ = ([], None) if heard_peak < SILENT_PEAK else coded(heard_path, t_heard, sent_peaks)
    pairs = pair(sent_on, heard_on)
    with open(out_path, "w") as f:
        for s, d in pairs:
            f.write(json.dumps({"sent": round(s, 4), "delay_ms": None if d is None else round(d * 1000)}) + "\n")
            f.flush()
    delays = sorted(d * 1000 for _, d in pairs if d is not None)
    return {"sent_start": round(t_sent, 4), "heard_start": round(t_heard, 4),
            "clicks_sent": len(sent_on), "clicks_heard": len(delays),
            "speech": speech, "heard_peak": heard_peak, "heard_beeps": len(heard_on),
            "heard_unpaired": len(heard_on) - len(delays),
            "delay_median_ms": round(statistics.median(delays)) if delays else None,
            "delay_min_ms": round(delays[0]) if delays else None,
            "delay_max_ms": round(delays[-1]) if delays else None}


def self_check(d, speech=False):
    """Known conditions: a 0.300 s delay and 3 of 9 clicks removed; the same
    at 10.300 s, which single clicks paired within 3 s read as 300 ms
    (calls23a); with speech, the same on the speech track, and a heard copy
    with every click removed must read no clicks heard, never speech taken
    for one."""
    os.makedirs(d, exist_ok=True)
    track = os.path.join(d, "track.wav")
    call_track(track, 9, speech)
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
    # The heard copy: clicks 3, 6, 9 (at 25, 55, 85 s) silenced; click 2
    # (15 s, 1100 Hz) at 0.35 of its level with a 2000 Hz tone at 0.28 on
    # top of it, as the codec left a weak beep and its leak into another
    # band (calls26: real beeps came through at 0.36-0.46 of the sent level
    # and their neighbours at 0.25-0.37, at the same instant); with speech, a
    # 1500 Hz beep (click 3's pitch) inside the speech at 28 s, as the codec
    # made beeps out of speech (calls26: 88 onsets in all, paired with a
    # click 27.9 s and 48 s after it was sent).
    edited = os.path.join(d, "heard.wav")
    with wave.open(track) as w:
        a = array("h", w.readframes(w.getnframes()))
    rate, n = 48000, int(BEEP_S * 48000)
    for k in (3, 6, 9):
        a[int((10 * k - 5 - 0.1) * rate):int((10 * k - 5 + 0.2) * rate)] = array("h", bytes(2 * int(0.3 * rate)))
    tone = lambda f, i, g: int(g * 0.8 * 32767 * math.sin(2 * math.pi * f * i / rate))
    for i in range(n):
        a[15 * rate + i] = tone(CODE_TONES[1], i, 0.35) + tone(CODE_TONES[3], i, 0.28)
        if speech:
            a[28 * rate + i] = tone(CODE_TONES[2], i, 1.0)
    with wave.open(edited, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(a.tobytes())
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", edited, heard])
    logged(heard, t + 0.3)
    starts_ok = (abs(start_time(sent) - (t + 0.002)) < 1e-4
                 and abs(start_time(heard) - (t + 0.302)) < 1e-4)
    got = measure(sent, heard, os.path.join(d, "pairs.jsonl"), speech)
    want = {"clicks_sent": 9, "clicks_heard": 6, "delay_median_ms": 300, "heard_unpaired": 0}
    # Click 2, at 0.35, crosses the bar later on its rise than a full beep:
    # 1 ms (301) when this was written; every full beep reads exactly.
    def exact(path, ms):
        d = [json.loads(l)["delay_ms"] for l in open(path)]
        return all(x == ms for i, x in enumerate(d) if i != 1 and x is not None) and abs(d[1] - ms) <= 2
    ok = (starts_ok and all(got[k] == v for k, v in want.items())
          and exact(os.path.join(d, "pairs.jsonl"), 300))
    late = os.path.join(d, "late.mkv")
    sh(["ffmpeg", "-y", "-loglevel", "error", "-i", heard, "-c", "copy", late])
    logged(late, t + 10.3)
    got["late"] = measure(sent, late, os.path.join(d, "pairs_late.jsonl"), speech)
    # Every click heard 10.3 s late, less the three removed (3, 6, 9).
    ok = (ok and got["late"]["clicks_heard"] == 6 and got["late"]["heard_unpaired"] == 0
          and exact(os.path.join(d, "pairs_late.jsonl"), 10300))
    if speech:
        every = "+".join(f"between(t,{10 * k - 5 - 0.1},{10 * k - 5 + 0.2})" for k in range(1, 10))
        none = os.path.join(d, "none.mkv")
        sh(["ffmpeg", "-y", "-loglevel", "error", "-i", track, "-af",
            f"volume=enable='{every}':volume=0", none])
        logged(none, t + 0.3)
        got["all_clicks_removed"] = measure(sent, none, os.path.join(d, "pairs_none.jsonl"), True)
        ok = ok and got["all_clicks_removed"]["clicks_heard"] == 0
    print(json.dumps({"self_check": "pass" if ok else "FAIL", "got": got, "want": want}), flush=True)
    return ok


if __name__ == "__main__":
    if sys.argv[1:2] == ["--self-check"]:
        sys.exit(0 if self_check(sys.argv[2]) else 1)
    if sys.argv[1:2] == ["--self-check-speech"]:
        sys.exit(0 if self_check(sys.argv[2], speech=True) else 1)
    print(json.dumps(measure(*sys.argv[1:4])), flush=True)
