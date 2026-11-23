# E5c results, 2026-11-22

Plan: docs/GATE2-CALLS-PLAN.md, "E5c PLAN". Runner `lab/e5/e5c_run.sh`
(exit 0, 48 calls). Gate 1's arrangement (only Alice shaped, both ways),
P1-P4 direct and relayed, 3 calls each, 3-minute calls.
B = flutter_webrtc 1.6.3, old code (video stopped with replaceTrack(null)).
F = 1.6.3 with the fix (video stopped and held with `active: false`).
Tables: `results/e5c_B.md`, `results/e5c_F.md`. Alice's video packets:
`results/e5c_video_packets.txt` (`video_packets.py`).

## Medians (3 calls each)

| Profile | E5b A voice ms | B voice ms | F voice ms | WhatsApp | E5b A frozen | B frozen | F frozen | WhatsApp |
|---|---|---|---|---|---|---|---|---|
| P1 direct | 16,383 | 649 | 725 | 696 | 60.0 | 60.0 | 60.0 | 14.2 |
| P1 relayed | 1,183 | 2,666 | 1,661 | 696 | 60.0 | 60.0 | 60.0 | 14.2 |
| P2 direct | 218 | 222 | 220 | unknown | 4.62 | 7.2 | 6.32 | 3.4 |
| P2 relayed | 211 | 218 | 230 | unknown | 4.22 | 4.48 | 5.62 | 3.4 |
| P3 direct | 447 | 444 | 439 | unknown | 4.35 | 4.45 | 4.71 | 6.0 |
| P3 relayed | 443 | 435 | 438 | unknown | 4.73 | 4.46 | 4.14 | 6.0 |
| P4 direct | 258 | 248 | 206 | - | 47.66 | 49.35 | 50.64 | - |
| P4 relayed | 206 | 217 | 199 | - | 59.7 | 59.8 | 59.87 | - |

P1 per call, voice median ms: E5b direct 10,942 / 16,383 / 17,074;
B direct 649 / 652 / 616; F direct 725 / 789 / 714. Relayed: E5b 1,492 /
1,183 / 903; B 9,443 / 749 / 2,666; F 1,661 / 984 / 10,544.

## What the fix did to the padding (P1, Alice's own stats)

Alice's video sent no frames in any P1 call, in any run: P1 never had the
bandwidth to start the picture. What it sent was padding. Video packets
over the last two thirds of each call:

- E5b A: direct 1,270 / 1,302 / 1,556 (about 11 a second, about 24
  kbit/s); relayed 114 / 124.
- B: direct 81 / 131 / 103; relayed 1,760 / 145 / 130.
- F: 154 / 154 / 104 / 120 / 0 / 0 (direct and relayed); the stream
  reported `active: false` throughout. At most about 1 packet a second.

So with the fix no call sent heavy padding (0 of 6, against 3 of 6 in
E5b A and 1 of 6 in B). The inactive stream still sent up to about 1
packet a second in 4 of 6 calls; why is not known. The loopback test
(0 packets in 10 s) did not show this.

## What it did not fix

- P1 voice still fails against WhatsApp: direct 725 ms against 696;
  relayed 1,661 ms. F3 P1 relayed ran 10.5 s behind with no padding at
  all (58 video packets in the whole call, none in the last two thirds);
  its uplink queue still reached 995 packets. So padding is not the only
  thing that fills Alice's 50 kbit/s uplink.
- P1 video: frozen 60 s/min in every run.
- P2 frozen video still fails (6.32 direct, 5.62 relayed, WhatsApp 3.4).

## The library update alone (B against E5b A)

P1 direct went from 16.4 s to 0.65 s; P1 relayed from 1.2 s to 2.7 s.
The heavy padding moved from all three direct calls (E5b) to one relayed
call (B1). Why the library changed when padding appears is not measured.
P2 direct frozen went from 4.62 to 7.2; one call (B1, 26.2) carries most
of that.

## Not checked

The voice cost of the sound itself on this link: Opus at 20 ms packets is
most of 50 kbit/s once packet headers are counted (unmeasured here); the
60 ms packet test (E5 step 1b: P1 direct 378 ms) is the next run against A.
