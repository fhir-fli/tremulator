| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [12485, 15034, 11035] (12485) | [57.85, 56.7, 58.11] (57.85) | [396, 363, 429] (396) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2 | 3 | host→host, host→host, host→host | [4543, 2998, 3713] (3713) | [4.14, 4.13, 4.12] (4.13) | [269, 287, 312] (287) | 17/17, 16/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [5928, 6507, 6643] (6507) | [59.83, 4.1, 4.42] (4.42) | [465, 535, 542] (535) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [3800, 3389, 3152] (3389) | [46.0, 45.53, 48.16] (46.0) | [308, 246, 256] (256) | 5/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [11077, 13248, 9966] (11077) | [60.0, 60.0, 60.0] (60.0) | [4765, 1511, 343] (1511) | 17/17, 14/17, 17/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2-blocked | 3 | host→relay, host→relay, host→relay | [4616, 3139, 2805] (3139) | [3.78, 3.8, 4.14] (3.8) | [314, 317, 286] (314) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [5978, 8347, 5700] (5978) | [4.82, 4.64, 4.25] (4.64) | [525, 522, 510] (522) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4-blocked | 3 | host→relay, host→relay, host→relay | [4145, 3474, 3977] (3977) | [47.15, 47.62, 45.02] (47.15) | [272, 266, 288] (272) | 4/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
