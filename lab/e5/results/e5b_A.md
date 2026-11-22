| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [10915, 10721, 11069] (10915) | [60.0, 60.0, 60.0] (60.0) | [10942, 16383, 17074] (16383) | 16/17, 17/17, 17/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2 | 3 | host→host, host→host, host→host | [3353, 3259, 2892] (3259) | [5.75, 4.62, 4.41] (4.62) | [254, 218, 207] (218) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [5682, 5671, 5689] (5682) | [4.66, 4.35, 4.13] (4.35) | [447, 448, 436] (447) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [3106, 3436, 3881] (3436) | [59.84, 47.66, 47.34] (47.66) | [183, 277, 258] (258) | 4/17, 4/17, 4/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [11586, 15281, 10909] (11586) | [60.0, 60.0, 60.0] (60.0) | [1492, 1183, 903] (1183) | 16/17, 17/17, 17/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2-blocked | 3 | host→relay, host→relay, host→relay | [2730, 3122, 3029] (3029) | [4.08, 5.23, 4.22] (4.22) | [211, 208, 226] (211) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [7752, 5675, 6383] (6383) | [4.92, 3.96, 4.73] (4.73) | [456, 443, 438] (443) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4-blocked | 3 | host→relay, host→relay, host→relay | [3193, 3427, 3663] (3427) | [59.87, 59.7, 46.2] (59.7) | [204, 206, 264] (206) | 5/17, 5/17, 4/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
