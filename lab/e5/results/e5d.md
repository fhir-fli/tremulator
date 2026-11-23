| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [11355, 10970, 13223] (11355) | [60.0, 60.0, 60.0] (60.0) | [513, 347, 546] (513) | 17/17, 17/17, 16/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2 | 3 | host→host, host→host, host→host | [3259, 3183, 2846] (3183) | [5.49, 6.9, 5.77] (5.77) | [266, 277, 265] (266) | 17/17, 17/17, 16/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [5748, 5693, 5679] (5693) | [4.49, 4.42, 4.81] (4.49) | [503, 493, 497] (497) | 17/17, 17/17, 16/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [3488, 3720, 3333] (3488) | [47.31, 60.0, 46.56] (47.31) | [341, 223, 312] (312) | 5/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [10622, 11052, 13119] (11052) | [60.0, 60.0, 60.0] (60.0) | [333, 335, 334] (334) | 17/17, 16/17, 16/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2-blocked | 3 | relay→host, host→relay, host→relay | [2835, 3967, 2724] (2835) | [18.93, 4.23, 5.82] (5.82) | [223, 296, 258] (258) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [6648, 5682, 5680] (5682) | [4.53, 4.16, 4.26] (4.26) | [519, 476, 468] (476) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4-blocked | 3 | host→relay, host→relay, host→relay | [3557, 3207, 3461] (3461) | [60.0, 60.0, 60.0] (60.0) | [226, 240, 226] (226) | 5/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
