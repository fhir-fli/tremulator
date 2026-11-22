| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [21088, 18889, 18751] (18889) | [60.0, 60.0, 60.0] (60.0) | [9326, 11634, 12997] (11634) | 16/17, 14/17, 17/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2 | 3 | host→host, host→host, host→host | [5620, 5113, 5364] (5364) | [6.19, 6.49, 6.18] (6.19) | [340, 217, 242] (242) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [12882, 9131, 9213] (9213) | [4.03, 4.29, 4.35] (4.29) | [570, 457, 484] (484) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [6052, 5826, 6048] (6048) | [46.43, 45.1, 43.76] (45.1) | [337, 272, 300] (300) | 4/17, 3/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P5 | 3 | host→host, host→host, host→host | [651, 788, 744] (744) | [4.08, 3.74, 3.74] (3.74) | [57, 108, 117] (108) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; connects: 3 of 3 |
| P0 | 3 | None, None, None | [None, None, None] (None) | [None, None, None] (None) | [None, None, None] (None) | None/None, None/None, None/None | connect: no WhatsApp number; gives_up_cleanly: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [22516, 24601, 20289] (22516) | [60.0, 60.0, 60.0] (60.0) | [22886, 17209, 16474] (17209) | 7/17, 12/17, 12/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2-blocked | 3 | host→relay, host→relay, host→relay | [5399, 5674, 5870] (5674) | [13.94, 9.46, 12.95] (12.95) | [306, 331, 439] (331) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [15740, 13661, 18225] (15740) | [8.89, 8.55, 8.45] (8.55) | [794, 791, 995] (794) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
