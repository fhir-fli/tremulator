# E5d: 60 ms sound packets, Alice's uplink shaped only (2026-11-22)

Plan: `docs/GATE2-CALLS-PLAN.md`, E5d. One change from E5c F (main with the
video fix, d90c0b1): `--opus-ptime 60` (20 ms before). Run: `e5d_run.sh`,
three passes of 8 profiles, 3-minute calls, Gate 1's arrangement A (only
Alice's link shaped). Table: `results/e5d.md`. Extra facts:
`results/e5d_video_packets.txt` (`video_packets.py`),
`results/e5d_queue_max.txt` (`queue_max.py`; checked against E5c F, where it
gives the known 995-packet peak on e5cF3 P1 relayed: `results/e5c_queue_max.txt`).

The setting took: Alice's link carried 4,862 packets on e5d1 P1 against about
10,800 at 20 ms.

| Profile | Voice median, E5c F → E5d (WhatsApp) | Bob frozen s/min, E5c F → E5d (WhatsApp) | Alice's queue peak, packets, E5c F → E5d |
|---|---|---|---|
| P1 direct | 725 → 513 ms, all 3 under (696) | 60 → 60 (14.2) | 50/132/202 → 26/127/17 |
| P1 relayed | 1,661 → 334 ms, all 3 under (696) | 60 → 60 (14.2) | 346/310/995 → 146/130/211 |
| P2 direct | 220 → 266 ms | 6.32 → 5.77 (3.4) | — |
| P2 relayed | 230 → 258 ms | 5.62 → 5.82 (3.4) | — |
| P3 direct | 439 → 497 ms | 4.71 → 4.49 (6.0), pass | — |
| P3 relayed | 438 → 476 ms | 4.14 → 4.26 (6.0), pass | — |
| P4 direct / relayed | 206 / 199 → 312 / 226 ms | survives 3 of 3 both | — |

P1 voice now passes on both routes (range 333-546 ms over 6 calls; E5c F had
one relayed call at 10.5 s). P1 video still never showed a frame. P2 still
fails frozen. On P2, P3 and P4 the voice is 30-110 ms later, which is the
expected cost of larger packets (40 ms more per packet); none of those
profiles has a WhatsApp voice number.

New, found in Alice's own events: with the round trip now low (0.44 and
0.52 s), the guard judged the P1 direct link steady and turned video on in
2 of 3 calls (e5d1, e5d3), about 3 s before the encoder paused it for lack
of bandwidth ("video-held"). The stream then stayed active with no frames
and sent about 1,250 header-only packets (about 23 kbit/s) over the last two
thirds of each call, the padding E5c removed. Voice still passed in those
calls (513, 546 ms). The guard looks at the round trip only, not at the
available bandwidth; a paused stream is not turned off. Both are measured
here, not yet fixed or tested.

Odd, not explained: e5d1 P2 relayed had the route recorded relay→host and
18.9 s/min frozen; the other two were 4.2 and 5.8.
