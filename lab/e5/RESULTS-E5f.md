# E5f: video's lowest rate 10 kbit/s (--video-min-kbps 10), against E5e (2026-11-24)

Plan: `docs/GATE2-CALLS-PLAN.md`, E5f. One change from E5e. Runner
`e5f_run.sh`; table `results/e5f.md`; extras `results/e5f_queue_max.txt`,
`results/e5f_start_signals.txt`, `results/e5f_video_packets.txt`,
`results/e5def_idle_video_packets.txt` (script `idle_video_packets.py`).

Hypothesis (from the plan): with the floor under the estimate, video fits
above the sound, the guard keeps it on, and P1 direct frozen falls below 60.
**Not met.**

| Profile | Voice median, E5e → E5f (WhatsApp) | Bob frozen s/min, E5e → E5f (WhatsApp) |
|---|---|---|
| P1 direct | 479 → 396 ms; calls 396, 363, 429 (696) | 58.29 → 57.85 (14.2) |
| P1 relayed | 342 → 1511 ms; calls 4765, 1511, 343 (696), fail | 60 → 60 (14.2) |
| P2 direct | 283 → 287 ms | 4.15 → 4.13 (3.4), fail |
| P2 relayed | 278 → 314 ms | 3.84 → 3.80 (3.4), fail |
| P3 direct / relayed | 494 / 487 → 535 / 522 ms | 4.62 / 4.67 → 4.42 / 4.64 (6.0), pass |
| P4 direct / relayed | survives 3 of 3 | survives 3 of 3 |

The setting took: opus-asked logs video-min-bitrate 10000 and the encoder
target sat at 10,000 bit/s when idle.

P1: the guard started video in 4 of 6 calls (all 3 direct, 1 relayed) and
stopped every one 6-10 s later. Each time video started, WebRTC's outgoing
estimate rose from 39 to 69-72 kbit/s, above the 50 kbit/s link, and the
encoder target followed it to 15-23 kbit/s. Round trip at start and stop:
0.44 → 1.63 s, 0.52 → 4.60 s, 1.41 → 13.7 s, 0.46 → 1.17 s. E5e (target
30,000) showed the same jump to 69.5. So a lower floor lowered the rate
video started at, but not the rate it climbed to.

Video packets with no media (padding: payload 0, about 279 bytes each) are
sent while video is off, in every variant (E5d, E5e, E5f): 17 in most calls,
hundreds to 1,755 in some (`e5def_idle_video_packets.txt`). In e5f1 P1
relayed video never started, yet padding ran at about 10 packets/s
(about 22 kbit/s) from 4 s to 96 s; the round trip rose to 5-9 s, the queue
to 340 packets, and voice delay was 4,765 ms. When it slowed at 96 s the
round trip fell to 0.44 s. Measured sequence, not shown cause by A/B.

Instrument fault: e5f1 P3's Bob recording is blank for the whole call
(three identical stills, dark screen), so it scores 59.83 frozen; Bob's
decoder counted 4,635 frames and 1.15 s of freezes. P3's median without it
is unchanged in verdict (4.10, 4.42).
