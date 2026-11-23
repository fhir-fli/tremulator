| Profile | Calls | Route | Connect ms (median) | Bob frozen s/min (median) | Voice ms (median) | Clicks heard | Verdict |
|---|---|---|---|---|---|---|---|
| P1 | 3 | host→host, host→host, host→host | [11053, 11188, 11447] (11188) | [58.13, 60.0, 58.29] (58.29) | [479, 326, 709] (479) | 17/17, 16/17, 16/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2 | 3 | host→host, host→host, host→host | [2859, 2931, 3189] (2931) | [4.15, 4.13, 4.19] (4.15) | [283, 288, 279] (283) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3 | 3 | host→host, host→host, host→host | [6487, 5694, 5700] (5700) | [4.43, 4.62, 4.8] (4.62) | [513, 488, 494] (494) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4 | 3 | host→host, host→host, host→host | [3304, 3103, 3286] (3286) | [47.02, 47.89, 47.09] (47.09) | [274, 232, 264] (264) | 3/17, 3/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
| P1-blocked | 3 | host→relay, host→relay, host→relay | [10146, 14095, 11127] (11127) | [60.0, 60.0, 60.0] (60.0) | [352, 342, 333] (342) | 16/17, 17/17, 16/17 | connect: no WhatsApp number; voice: pass; frozen: fail |
| P2-blocked | 3 | host→relay, host→relay, host→relay | [2901, 3033, 3007] (3007) | [3.84, 4.16, 3.84] (3.84) | [285, 260, 278] (278) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: fail |
| P3-blocked | 3 | host→relay, host→relay, host→relay | [6381, 5691, 6436] (6381) | [4.89, 4.09, 4.67] (4.67) | [521, 483, 487] (487) | 17/17, 17/17, 17/17 | connect: no WhatsApp number; voice: no WhatsApp number; frozen: pass |
| P4-blocked | 3 | host→relay, host→relay, host→relay | [3905, 3315, 3368] (3368) | [46.64, 50.34, 47.59] (47.59) | [282, 242, 228] (242) | 5/17, 5/17, 5/17 | connect: no WhatsApp number; survives_drop: 3 of 3 |
