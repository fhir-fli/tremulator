# E5g: loss-based padding off (2026-11-25)

One change from E5f: libwebrtc field trial
`WebRTC-Bwe-LossBasedBweV2/PaddingDuration:0ms/`, passed through the vendored
flutter_webrtc `fieldTrials` option (third_party/flutter_webrtc,
lab/e5/PADDING.md). Everything else as E5f: 60 ms Opus, no suspend, video
floor 10 kbit/s, Alice's link shaped, 3 passes of P1-P4 direct and relayed,
180 s calls. Script: lab/e5/e5g_run.sh. Runs: lab/gate2/results/e5g1-3.

Hypothesis: idle video packets fall to ~17 per call; P1 relayed voice under
696 ms in all calls; P1 frozen unchanged; P2/P3 may worsen.

## Medians of 3 calls (WhatsApp Gate 1 in brackets)

| Profile | Voice ms E5f | Voice ms E5g | Frozen s/min E5f | Frozen s/min E5g |
|---|---|---|---|---|
| P1 direct | 396 | 370 (353/370/484) [696] | 57.85 | 57.63 [14.2] |
| P1 relayed | 1,511 (4,765/1,511/343) | 365 (365/350/887) [696] | 60 | 60 [14.2] |
| P2 direct | | 247 | 4.13 | 4.16 (20.48/4.14/4.16) [3.4] |
| P2 relayed | | 207 | 3.80 | 4.15 (4.01/4.15/27.39) [3.4] |
| P3 direct | | 499 | 4.42 | 4.49 [6.0] |
| P3 relayed | | 496 | 4.64 | 4.12 [6.0] |

P4 survives the drop 3 of 3 direct and relayed. Table: results/e5g.md.

## Findings

1. Padding with video off is gone. Video packets sent while the encoding is
   inactive: 17-20 in all 18 lossy calls (18 in e5g3 P1 relayed), the
   handshake baseline (results/e5g_idle_video_packets.txt). E5f had up to
   1,131. So the loss-based estimator was the source of that padding: A/B,
   one variable.
2. P1 relayed voice: 365 / 350 / 887 ms. Two of three under WhatsApp's 696;
   the hypothesis said all three, so it is not met. In e5g3 P1 relayed the
   guard turned video on at 24 s and off at 33 s; Alice's queue reached 104
   packets. Measured sequence, not shown cause. The 4,765 ms E5f call did not
   recur.
3. P1 frozen unchanged (57.63 / 60). Video still cannot stay on at 50 kbit/s;
   start signals as E5f (estimate 39 -> 69 on video start, guard stops it
   after 7-9 s).
4. P2 got worse in 2 of 6 calls. Alice's estimate stayed at 69-90 kbit/s for
   the whole call in 3 of 6 E5g P2 calls; in E5f all 6 climbed to ~230-270
   within 60 s (results/e5fg_p2_whole_call_estimate.txt,
   whole_call_estimate.py). Two of the stuck calls decoded 417 and 376 frames
   at Bob (about 2 per second; others ~4,600) and froze 20.48 and 27.39 s/min.
   So the padding was what raised the estimate on P2: measured A/B on the
   estimate; the frame-rate drop follows from it in the same calls.
5. Recordings: none blank. Bob's P1-relayed stills show "Their video is off:
   weak connection" as expected (results/e5g_bob_still_sizes.txt).

## Where it leaves us

Padding off fixes the P1 relayed voice blow-up most of the time but leaves P2
stuck at a low estimate in half the calls. P1 frozen and P2 frozen still fail.
