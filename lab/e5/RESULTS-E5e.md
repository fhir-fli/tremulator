# E5e: video never paused (--no-suspend-video), against E5d (2026-11-23)

Plan: `docs/GATE2-CALLS-PLAN.md`, E5e. One change from E5d. Runner
`e5e_run.sh`; table `results/e5e.md`; extras `results/e5e_queue_max.txt`,
`results/e5e_start_signals.txt`, `results/e5e_video_packets.txt`.

| Profile | Voice median, E5d → E5e (WhatsApp) | Bob frozen s/min, E5d → E5e (WhatsApp) |
|---|---|---|
| P1 direct | 513 → 479 ms; calls 479, 326, 709 (696) | 60 → 58.29; calls 58.13, 60, 58.29 (14.2) |
| P1 relayed | 334 → 342 ms (696) | 60 → 60 (14.2) |
| P2 direct | 266 → 283 ms | 5.77 → 4.15 (3.4), fail |
| P2 relayed | 258 → 278 ms | 5.82 → 3.84 (3.4), fail |
| P3 direct / relayed | 497 / 476 → 494 / 487 ms | 4.49 / 4.26 → 4.62 / 4.67 (6.0), pass |
| P4 direct / relayed | survives 3 of 3 | survives 3 of 3 |

P1: the guard started video in 2 of 3 direct calls (12 s and 21 s after
connect) and none relayed (it turned video off at 9-13 s, as in E5d). Once
started, video ran at its minimum: the encoder's target was 30,000 bit/s,
320 wide, 10-19 frames/s, about 31 kbit/s sent. With the sound (about
15 kbit/s) that is more than the 50 kbit/s link carries: the round trip went
from 0.44 s to 2.2-2.7 s within 8 s and the guard stopped video after 9 s
and 8 s (105 and 120 frames sent). One P1 direct call's voice (709 ms) was
over WhatsApp's 696.

P2: with no pause, the holds at the start of E5d's P2 calls are gone and
frozen fell by about 2 s/min, to within 0.4-0.8 s/min of WhatsApp.

Still unexplained: in e5e1 P1, 227 video packets with no frames were sent
over the last two thirds of the call after video was turned off (active
false), about 1.9 per second; the same trickle E5c recorded.
