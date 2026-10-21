"""Run from lab/gate2. For each click Bob missed in calls26 P1/P1-blocked, the heard band's peak near where it
should have arrived (sent + median delay of that run, -150..+250 ms), as a fraction of the
sent beep's peak in that band. Paired clicks' fractions for comparison."""
import json, os, statistics, sys, wave
from array import array
sys.path.insert(0, ".")
import voice_delay as vd
OUT = sys.argv[1]

def window(wav, t0, t1):
    with wave.open(wav) as w:
        r = w.getframerate()
        w.setpos(max(0, min(w.getnframes(), int(t0 * r))))
        a = array("h", w.readframes(int((t1 - t0) * r)))
    return max((abs(x) for x in a), default=0)

with open(OUT, "w") as out:
    for prof in ["P1", "P1-blocked"]:
        for r in [1, 2, 3]:
            for arm in ["fc", "fd"]:
                d = f"results/calls26{r}{arm}/{prof}"
                rows = [json.loads(l) for l in open(f"{d}/voice_delay.jsonl")]
                ts, th = vd.start_time(f"{d}/alice_sent.mkv"), vd.start_time(f"{d}/bob_heard.mkv")
                med = statistics.median([x["delay_ms"] for x in rows if x["delay_ms"] is not None]) / 1000
                peaks = [vd.peak(f"{d}/alice_sent_band{t}.wav") for t in vd.CODE_TONES]
                for i, x in enumerate(rows):
                    code = i % 6
                    wav = f"{d}/bob_heard_band{vd.CODE_TONES[code]}.wav"
                    if x["delay_ms"] is None:
                        at = x["sent"] + med - th
                        lvl = window(wav, at - 0.15, at + 0.25 + vd.BEEP_S)
                    else:
                        at = x["sent"] + x["delay_ms"] / 1000 - th
                        lvl = vd.level_at(wav, at)
                    out.write(json.dumps({"run": f"{r}{arm}", "profile": prof, "click": i, "code": code,
                                          "missed": x["delay_ms"] is None,
                                          "fraction": round(lvl / peaks[code], 2)}) + "\n")
                    out.flush()
