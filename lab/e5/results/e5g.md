| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [10496, 11917, 20347] (11917) | [57.63, 57.88, 55.07] (57.63) | [353, 370, 484] (370) | 17/17, 17/17, 16/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2 | 3 | host→host, host→prflx, host→host | [2703, 3103, 3054] (3054) | [20.48, 4.14, 4.16] (4.16) | [204, 281, 247] (247) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [6339, 7052, 5592] (6339) | [4.49, 4.31, 4.8] (4.49) | [499, 496, 512] (499) | 16/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [4712, 3122, 3048] (3122) | [50.04, 47.4, 46.85] (47.4) | [228, 237, 234] (234) | 4/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [11436, 11026, 12426] (11436) | [60.0, 60.0, 56.54] (60.0) | [365, 350, 887] (365) | 17/17, 17/17, 16/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2-blocked | 3 | host→relay, host→relay, host→relay | [2808, 3053, 2729] (2808) | [4.01, 4.15, 27.39] (4.15) | [207, 271, 204] (207) | 16/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [5702, 5705, 5595] (5702) | [4.3, 4.12, 4.1] (4.12) | [496, 498, 483] (496) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4-blocked | 3 | host→relay, host→relay, host→relay | [3222, 3048, 3246] (3222) | [50.29, 48.37, 48.82] (48.82) | [247, 249, 229] (247) | 5/17, 5/17, 4/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
