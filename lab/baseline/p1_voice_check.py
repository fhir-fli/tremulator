#!/usr/bin/env python3
"""Checks GATE1.md's only WhatsApp voice number (P1, 690-696 ms) against the
call's own media. Finds click onsets in results/p1-clap.wav (amplitude, 0.5
of the peak after the first second, mean removed, 150 ms dead time) and
places them on the wall clock: audio.log stamps a recording when it ENDS
(audio_delay.sh writes the line after ffmpeg returns), so start = stamp -
length. Then finds the first UDP packet to or from Meta's relay (port 3478)
in results/p1.pcap.

    cd lab/baseline && python3 p1_voice_check.py > results/p1_voice_check.txt
"""
import datetime, struct, wave
w = wave.open("results/p1-clap.wav"); n = w.getnframes(); sr = w.getframerate()
x = struct.unpack("<%dh" % n, w.readframes(n))
s = sr; m = sum(x[s:]) / (n - s); y = [abs(v - m) for v in x]
th = 0.5 * max(y[s:]); on = []; last = -1e9
for i in range(s, n):
    if y[i] >= th:
        if i - last > 0.15 * sr: on.append(i / sr)
        last = i
end = None
for line in open("results/audio.log"):
    if " p1-clap " in line:
        end = datetime.datetime.fromisoformat(line.split()[0]).timestamp()
start = end - n / sr
f = open("results/p1.pcap", "rb"); f.read(24); first = None
while first is None:
    h = f.read(16)
    if len(h) < 16: break
    ts, tu, cl, ol = struct.unpack("<IIII", h); d = f.read(cl)
    if d[12:14] != b"\x08\x00": continue
    ip = d[14:]
    if ip[9] != 17: continue
    ihl = (ip[0] & 15) * 4; sp, dp = struct.unpack(">HH", ip[ihl:ihl + 4])
    if 3478 in (sp, dp) and ts > start: first = ts + tu / 1e6
fmt = lambda t: datetime.datetime.fromtimestamp(t).strftime("%H:%M:%S.%f")[:-3]
print("recording", fmt(start), "to", fmt(end), flush=True)
print("first relay packet", fmt(first), flush=True)
for a, b in zip(on, on[1:]):
    if b - a < 1.0:
        print(f"pair {a:.3f}/{b:.3f} s, gap {1000*(b-a):.0f} ms, at {fmt(start+a)},",
              "BEFORE the call's first media" if start + b < first else "during media", flush=True)
print("onsets", [round(t, 3) for t in on], flush=True)
