"""How far Bob's sound and picture drift apart while video is on (E7, Grey
"ok" 2026-10-21). With --lip-drift, a box in Alice's test picture is black
and turns white for FLASH_S every FLASH_EVERY_S. Each phone grabs just that
box off its own screen, stamping every frame with the wall clock (the same
clock on every container: they share the host's), so a flash's onset is
placed on Alice's screen (what she sent) and on Bob's (what he saw). Video
delay = Bob's onset - Alice's. The voice delay comes from the clicks
(voice_delay.jsonl). Drift = voice delay - video delay at the nearest click:
positive means the sound arrives after the picture.

Bob's remote picture fills his 1280x720 screen as Alice's test pattern fills
hers (calls281P2fc bob_screen_50.png against alice_screen_50.png), so the box
is at the same place on both.

usage: python3 lip_drift.py OUT.jsonl LABEL...     (from lab/gate2)
       python3 lip_drift.py --check DIR SHIFT_MS   (calls_lip_drift_check.sh)"""
import json
import os
import re
import statistics
import sys

import voice_delay

FLASH_EVERY_S = 10
FLASH_S = 1
BOX = (40, 560, 160, 120)  # x, y, w, h: lower left, clear of the moving line
WHITE = 125  # luma between the black box (16) and the white one (235)
PAIR_S = 5  # Bob's onset is paired with Alice's latest within this


def picture_filter():
    """testsrc2 plus the box: black, white for FLASH_S every FLASH_EVERY_S."""
    x, y, w, h = BOX
    return (f"testsrc2=size=1280x720:rate=30,"
            f"drawbox=x={x}:y={y}:w={w}:h={h}:color=black:t=fill,"
            f"drawbox=x={x}:y={y}:w={w}:h={h}:color=white:t=fill:"
            f"enable='lt(mod(t\\,{FLASH_EVERY_S})\\,{FLASH_S})'")


def grab_cmd(stem, cap_s):
    """Grab only the box at 30 frames a second and log each frame's wall
    time and mean luma to <stem>_flash.log. `timeout -s INT` caps it, as in
    voice_delay.record_cmd; the caller stops it with SIGINT."""
    x, y, w, h = BOX
    return (f"exec timeout -s INT {cap_s} ffmpeg -y -nostdin -hide_banner -nostats -loglevel error "
            f"-use_wallclock_as_timestamps 1 -f x11grab -framerate 30 -video_size {w}x{h} -i :0+{x},{y} "
            f"-copyts -vf signalstats,metadata=print:key=lavfi.signalstats.YAVG:file={stem}_flash.log "
            f"-f null - > {stem}_flash_record.log 2>&1")


# pts, not pts_time: metadata=print writes pts_time with six significant
# figures (1.79263e+09 for every frame, lipcheck0). Wall-clock stamps are in
# microseconds (x11grab's time base; the pts read as the wall time in us).
FRAME = re.compile(r"pts:(\d+)")
YAVG = re.compile(r"lavfi\.signalstats\.YAVG=([0-9.]+)")


def onsets(log):
    """Wall times of the first white frame after a black one."""
    out, t, was = [], None, None
    for line in open(log, errors="replace"):
        m = FRAME.search(line)
        if m:
            t = int(m.group(1)) / 1e6
            continue
        m = YAVG.search(line)
        if m and t is not None:
            white = float(m.group(1)) >= WHITE
            if white and was is False:
                out.append(t)
            was = white
    return out


def video_delays(sent, seen):
    """(Alice's onset, Bob's onset - Alice's) for each of Bob's onsets."""
    out = []
    for b in seen:
        before = [a for a in sent if a <= b and b - a < PAIR_S]
        if before:
            out.append((before[-1], b - before[-1]))
    return out


def drift(d):
    """Per flash: video delay, voice delay at the nearest click, drift (ms)."""
    sent = onsets(os.path.join(d, "alice_flash.log"))
    seen = onsets(os.path.join(d, "bob_flash.log"))
    clicks = [x for x in map(json.loads, open(os.path.join(d, "voice_delay.jsonl")))
              if x["delay_ms"] is not None]
    rows = []
    for t, v in video_delays(sent, seen):
        near = min(clicks, key=lambda c: abs(c["sent"] - t), default=None)
        if near is None or abs(near["sent"] - t) > FLASH_EVERY_S:
            continue
        rows.append({"t": round(t, 3), "video_ms": round(1000 * v),
                     "voice_ms": near["delay_ms"], "drift_ms": near["delay_ms"] - round(1000 * v)})
    return len(sent), len(seen), rows


def check(d, shift_ms):
    """calls_lip_drift_check.sh: flash and beep come from one player on one
    screen; the beep was delayed by shift_ms. The measured offset (beep onset
    - flash onset, both off the same phone) should read shift_ms."""
    flashes = onsets(os.path.join(d, "check_flash.log"))
    path = os.path.join(d, "check_sound.mkv")
    start = voice_delay.start_time(path)
    beeps = [start + t for t in voice_delay.onsets(voice_delay.to_wav(path, 1500))]
    offsets = []
    for f in flashes:
        near = min(beeps, key=lambda b: abs(b - f), default=None)
        if near is not None and abs(near - f) < PAIR_S:
            offsets.append(round(1000 * (near - f)))
    print(json.dumps({"shift_ms": shift_ms, "flashes": len(flashes), "beeps": len(beeps),
                      "offsets_ms": offsets,
                      "median_ms": statistics.median(offsets) if offsets else None}), flush=True)


if __name__ == "__main__":
    if sys.argv[1] == "--check":
        check(sys.argv[2], int(sys.argv[3]))
        sys.exit(0)
    with open(sys.argv[1], "a") as out:
        for label in sys.argv[2:]:
            p = os.path.join("results", f"{label}.jsonl")
            if not os.path.exists(p):
                continue
            for line in open(p):
                r = json.loads(line)
                if "profile" not in r:
                    continue
                d = os.path.join("results", label, r["profile"])
                if not os.path.exists(os.path.join(d, "alice_flash.log")):
                    continue
                n_sent, n_seen, rows = drift(d)
                ds = [x["drift_ms"] for x in rows]
                out.write(json.dumps({
                    "run": label, "profile": r["profile"], "opus": r.get("opus"),
                    "flashes_sent": n_sent, "flashes_seen": n_seen, "paired": len(rows),
                    "drift_median_ms": round(statistics.median(ds)) if ds else None,
                    "drift_range_ms": [min(ds), max(ds)] if ds else None,
                    "video_median_ms": round(statistics.median(x["video_ms"] for x in rows)) if rows else None,
                    "voice_median_ms": round(statistics.median(x["voice_ms"] for x in rows)) if rows else None,
                    "rows": rows,
                }) + "\n")
                out.flush()
