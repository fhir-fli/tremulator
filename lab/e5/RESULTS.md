# E5: our calls against WhatsApp's Gate 1 numbers (2026-11-21)

Plan and rules: `docs/GATE2-CALLS-PLAN.md`, E5 plan, fixed before any run;
three amendments written there before any run (WhatsApp connect time
unknown, P0 rule, the ~12 s video start). Runs: `run.sh` (e5r1-e5r3) and
`catchup.sh` (e5r1b, e5r2b: the 9 calls lost when the onset detector hung
past 600 s, twice, under `dart run`; it now runs from a compiled kernel
file and gives the same result on e5r1 P2). Three 3-minute video calls per
profile, shipped defaults. Table built by `table.py`: `results/TABLE.md`,
`results/table.jsonl`.

| Profile | Route | Connect, median | Bob frozen s/min, median (WhatsApp) | Voice median (WhatsApp) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|
| P1 2G | direct | 18.9 s | 60.0, all 3 (14.2) | 11.6 s (690-696 ms) | 16, 14, 17 of 17 | **fail** voice, frozen |
| P1 relayed | relay | 22.5 s | 60.0, all 3 (14.2) | 17.2 s | 7, 12, 12 of 17 | **fail** voice, frozen |
| P2 3G | direct | 5.4 s | 6.19 (3.4) | 242 ms (none) | 17 of 17 each | **fail** frozen |
| P2 relayed | relay | 5.7 s | 12.95 (3.4) | 331 ms | 17 of 17 each | **fail** frozen |
| P3 satellite | direct | 9.2 s | 4.29 (6.0) | 484 ms (none) | 17 of 17 each | pass frozen |
| P3 relayed | relay | 15.7 s | 8.55 (6.0) | 794 ms | 17 of 17 each | **fail** frozen |
| P4 drops | direct | 6.0 s | 45.1 | 300 ms | 4, 3, 5 of 17 | pass: 3 of 3 held to hang-up and carried sound after reconnecting (WhatsApp died ~25 s after the cut) |
| P5 no internet | direct | 0.74 s | 3.74 | 108 ms | 17 of 17 each | pass: 3 of 3 connected (WhatsApp never rang) |
| P0 dead | — | — | — | — | — | pass by the amended rule, 3 of 3: see below |

Connect time: no pass or fail; WhatsApp's is unknown (the answer moment
was never logged). Fingerprints: 0 hits at the server in all 24 placed
calls, 2 in the control each time. Every app exited 0 except P0.

P0, as measured: Alice's app could not register with the server ("No
route to host") and the lab app stopped with an error (exit 2) after
about 15 s; no call was placed. That meets the amended rule, but it tests
registration, not what a caller sees pressing call on a dead link.

Every WhatsApp call was relayed, so the relayed rows are the closer
comparison; they are worse than the direct ones on every profile.

Derived, not measured separately: the video starts about 12 s after
connect (the shipped pause-video-below-minimum setting; e4a Bob's
remote-video 12.1 s after connected). Over a 3-minute call that is about
4 s/min of the frozen figure. P2 direct without it would be about 2.2,
under WhatsApp's 3.4. The rule counts it, so P2 stays a fail.

Not checked: why P1's voice runs 9-23 s behind (recorded, not explained);
the cause of the `dart run` hang (removed, not found).
