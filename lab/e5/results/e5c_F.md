| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [10729, 15881, 14301] (14301) | [60.0, 60.0, 60.0] (60.0) | [725, 789, 714] (725) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2 | 3 | host→host, host→host, host→host | [3672, 4433, 2945] (3672) | [6.32, 4.31, 8.4] (6.32) | [202, 220, 231] (220) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [6372, 6385, 5687] (6372) | [4.71, 4.19, 4.81] (4.71) | [440, 431, 439] (439) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [3583, 3208, 3113] (3208) | [45.65, 50.64, 59.88] (50.64) | [222, 206, 192] (206) | 5/17, 4/17, 4/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [10286, 11674, 10533] (10533) | [60.0, 60.0, 60.0] (60.0) | [1661, 984, 10544] (1661) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: fail; frozen: fail |
| P2-blocked | 3 | host→relay, host→relay, host→relay | [2989, 3078, 2847] (2989) | [5.1, 6.43, 5.62] (5.62) | [213, 240, 230] (230) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [8733, 7186, 5729] (7186) | [4.14, 3.95, 4.19] (4.14) | [438, 445, 438] (438) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4-blocked | 3 | host→relay, host→relay, host→relay | [3202, 3213, 3313] (3213) | [59.91, 59.84, 59.87] (59.87) | [193, 199, 199] (199) | 5/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
