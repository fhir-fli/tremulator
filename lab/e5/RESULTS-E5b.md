# E5b results, 2026-11-22

Plan: docs/GATE2-CALLS-PLAN.md, "E5b PLAN" (Grey's go "yes"). Runner
`lab/e5/e5b_run.sh`, instrument check `lab/e5/e5b_check.sh` (passed: +543 ms
voice, Alice RTT 1.0005 s, netem only on Alice, both directions through it).
48 calls, shipped defaults, 3 per row. Tables: `results/e5b_A.md`,
`results/e5b_C.md`; raw per call `lab/gate2/results/e5bA1-3`, `e5bC1-3`.

## A: only Alice shaped, both ways (Gate 1's arrangement)

| Profile | Voice ms (median) | WhatsApp voice | Frozen s/min on Bob (median) | WhatsApp frozen | Verdict |
|---|---|---|---|---|---|
| P1 direct | 16,383 | 696 | 60.0 | 14.2 | fail, fail |
| P1 relayed | 1,183 | 696 | 60.0 | 14.2 | fail, fail |
| P2 direct | 218 | unknown | 4.62 | 3.4 | frozen fail |
| P2 relayed | 211 | unknown | 4.22 | 3.4 | frozen fail |
| P3 direct | 447 | unknown | 4.35 | 6.0 | frozen pass |
| P3 relayed | 443 | unknown | 4.73 | 6.0 | frozen pass |
| P4 direct | 258 | - | 47.66 | - | survives drop 3/3 |
| P4 relayed | 206 | - | 59.7 | - | survives drop 3/3 |

Clicks heard 16-17/17 in P1-P3; 4-5/17 in P4 (the link is cut for most of
each cycle). Connect median 10.9 s (P1), 3.3 s (P2), 5.7 s (P3); WhatsApp's
connect time is unknown (`whatsapp_connect.py`).

P1 direct is worse than P1 relayed (16.4 s against 1.2 s). Measured: the
queue on Alice's uplink reached its 1,000-packet cap in all 3 direct calls
and peaked at 291-387 packets relayed; Alice sent about the same bytes
(0.90-0.97 MB direct, 0.91-0.92 MB relayed). Why the queue differs: not
yet measured.

## C: only Bob shaped (ground server and relay on the clinic LAN)

Reported only; Gate 1 has no such call.

| Profile | Voice ms (median) | Frozen s/min on Bob (median) |
|---|---|---|
| P1 direct | 12,127 | 60.0 |
| P1 relayed | 2,556 | 60.0 |
| P2 direct | 223 | 4.44 |
| P2 relayed | 216 | 4.44 |
| P3 direct | 445 | 4.77 |
| P3 relayed | 443 | 3.98 |
| P4 direct | 201 | 59.21 |
| P4 relayed | 183 | 59.7 |

## Limits

- Only Alice sends video. In A, frozen video is measured on Bob, across
  Alice's shaped uplink; Gate 1 measured the shaped phone receiving.
- P1's known causes (video padding at 17-19 kbit/s with no frames; 20 ms
  Opus packets) are untouched here: shipped defaults. Steps 1 and 1b
  (`RESULTS.md`) showed each moves P1; next they are tested against A, one
  at a time.
