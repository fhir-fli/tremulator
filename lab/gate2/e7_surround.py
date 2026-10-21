"""Run from lab/gate2. Every onset heard in each tone's band in the calls26
runs, with how loud the whole recording is around it. The click track keeps
SPEECH_GAP_S of quiet either side of each beep, so a real beep should arrive
with quiet around it, and a beep the codec made out of speech should not.
Each onset is labelled by whether voice_delay.measure paired it with a
click; the question is whether the surround separates the two.

usage: python3 e7_surround.py OUT.jsonl"""
import json
import statistics
import sys
import wave
from array import array

sys.path.insert(0, ".")
import voice_delay as vd

RUNS = [f"calls26{r}{arm}/{prof}" for r in (1, 2, 3)
        for arm, profs in (("fc", ("P1", "P1-blocked")), ("fd", ("P1", "P1-blocked")),
                           ("dc", ("P1-blocked",)), ("dd", ("P1-blocked",)))
        for prof in profs]
# (before, after) windows around the onset, seconds; each after-window
# starts clear of the beep's own decay. The first pass used only the widest
# (calls26: 23 of 480 paired beeps had sound in it, all but one in the
# control runs, where the receiver sped playback up by up to 2.8 s a call,
# which cuts quiet first).
WINDOWS = {"w0.8": ((-0.8, -0.15), (0.2, 0.8)), "w0.5": ((-0.5, -0.15), (0.2, 0.5)),
           "w0.3": ((-0.3, -0.1), (0.15, 0.3))}


def load(path):
    with wave.open(path) as w:
        return w.getframerate(), array("h", w.readframes(w.getnframes()))


def peak(rate, a, t0, t1):
    i, j = max(0, int(t0 * rate)), max(0, min(len(a), int(t1 * rate)))
    return max((abs(x) for x in a[i:j]), default=0)


with open(sys.argv[1], "w") as out:
    for run in RUNS:
        d = f"results/{run}"
        rows = [json.loads(l) for l in open(f"{d}/voice_delay.jsonl")]
        heard_at = [x["sent"] + x["delay_ms"] / 1000 for x in rows if x["delay_ms"] is not None]
        th = vd.start_time(f"{d}/bob_heard.mkv")
        sent_peaks = [vd.peak(f"{d}/alice_sent_band{t}.wav") for t in vd.CODE_TONES]
        rate, full = load(vd.to_wav(f"{d}/bob_heard.mkv"))
        for code, tone in enumerate(vd.CODE_TONES):
            wav = f"{d}/bob_heard_band{tone}.wav"
            for t in vd.onsets(wav):
                beep = peak(rate, full, t, t + vd.BEEP_S + 0.02)
                around = {k: max(peak(rate, full, t + b[0], t + b[1]), peak(rate, full, t + a[0], t + a[1]))
                          for k, (b, a) in WINDOWS.items()}
                paired = any(abs(th + t - h) < 0.002 for h in heard_at)
                out.write(json.dumps({
                    "run": run, "code": code, "t": round(t, 3), "paired": paired,
                    "band_fraction": round(vd.level_at(wav, t) / sent_peaks[code], 2),
                    **{k: round(v / max(beep, 1), 3) for k, v in around.items()}}) + "\n")
                out.flush()
        print(run, "done", flush=True)
