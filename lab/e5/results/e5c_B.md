| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [20494, 9795, 10080] (10080) | [60.0, 60.0, 60.0] (60.0) | [649, 652, 616] (649) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2 | 3 | host→host, host→host, host→host | [2845, 3444, 3273] (3273) | [26.21, 7.2, 4.38] (7.2) | [261, 222, 207] (222) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [11310, 6388, 5933] (6388) | [16.78, 4.14, 4.45] (4.45) | [475, 439, 444] (444) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [3418, 3319, 3146] (3319) | [49.35, 59.81, 46.41] (49.35) | [259, 189, 248] (248) | 5/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [12992, 19135, 10965] (12992) | [60.0, 60.0, 60.0] (60.0) | [9443, 749, 2666] (2666) | 13/17, 16/17, 17/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2-blocked | 3 | host→relay, host→relay, host→relay | [3752, 2824, 3035] (3035) | [5.72, 4.45, 4.48] (4.48) | [218, 217, 218] (218) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [5924, 6432, 5679] (5924) | [4.5, 4.46, 4.29] (4.46) | [431, 435, 463] (435) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4-blocked | 3 | host→relay, host→relay, host→relay | [4136, 3195, 3945] (3945) | [59.8, 59.86, 46.63] (59.8) | [217, 187, 275] (217) | 4/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
