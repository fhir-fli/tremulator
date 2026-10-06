# Gate 1: build and validate the instruments

Started 2026-09-21. Criteria are in [SUCCESS.md](SUCCESS.md); this file says
how each is being met and what is blocked.

| Criterion | How | State |
|---|---|---|
| Five network profiles reproducible to ±10% | Docker lab, `tc netem` on each end; instrument in Dart (`lab/tool`), validated in Python first | **met, with one declared exception** (below) |
| Instrument fails a 0 kbit/s link and passes P5 | same lab | **met**: P0 no replies and no connection, twice; P5 passes, its no-internet check has a working positive control |
| Adversary harness: no plaintext in server storage or traffic | canary scanner over files and packet captures | **met**: 13/13 encoding checks, Python and Dart identical on 16 saved cases |
| Harness catches at least 5 injected defects | toy messenger with switchable defects | **met**: correct toy clean, 7/7 defects caught, four times (Python m2, m3; Dart d1, d2) |
| WhatsApp baseline on all five profiles | two phones through the shaped link | **met 2026-10-06**: P0–P5 measured, table below; two declared instrument changes |

## Network verdict, 2026-09-22

`lab/network/results/gate1_network_final.{json,txt}`, produced by
`lab/tool/bin/gate1_verdict.dart`. 19 checks.

| Profile | RTT (target) | Delivered rate vs expected | Loss (target), long runs | Other |
|---|---|---|---|---|
| P1 | 419 / 419 ms (400) | 46.7 / 47.4 kbit/s vs 45.6 | 4.914 / 4.918 % (5) | |
| P2 | 203 / 203 ms (200) | 286.3 / 286.3 vs 282.1 | 1.974 / 1.966 % (2) | internet control reachable |
| P3 | 701 / 701 ms (700) | 941.9 / 941.9 vs 950.1 | 1.061 / 1.030 % (1) | |
| P4 | 254 / 253 ms (250) | 285.9 / 285.9 vs 282.1 | 1.967 / 2.118 % (2) | up 29.7, 29.5 / 29.7, 29.7 s; down 60.3, 60.5 s |
| P5 | 5.3 / 5.3 ms (5) | 9.595 / 9.595 Mbit/s | 0 / 0 % | no internet route |
| P0 | — | — | — | no replies, no connection, twice |

RTT is target plus the time to clock a small packet through the rate cap
(P1: about 19 ms at 50 kbit/s). Every run-to-run difference is inside ±10%
(largest: P4 loss, 7.6%).

**Under the criteria exactly as written beforehand, two checks fail**: the
per-measurement 95% interval for P3 loss in loss-a (1.061%, interval
1.007–1.116) and P4 loss in loss-b (2.118%, interval 2.01–2.23). The link is not
at fault. Pooled over all 27 loss measurements from every run, the spread around
the targets is what chance predicts: sum of squared z 29.2 against about 27,
p = 0.35. Three measurements fell outside their 95% interval where about 1.4
are expected; three or more by chance happens about one time in seven. The
per-measurement rule fails a correct link by construction once there are many
checks. **Declared 2026-09-22, before any further runs: loss is judged by the
pooled test from now on.** The two failures stay recorded as failures.

**The Dart validator reproduces it** (run `dart1`, 2026-09-22, the instrument
we keep): all 19 checks pass first time with no retries, and every metric is
within ±4% of the Python runs' mean (largest: P4 loss, −4.0%).

Loss runs had to be long: at 2,000 datagrams, chance alone moves measured loss
about 15% between identical runs, which a ±10% rule cannot survive. Loss tests
are now sized from the target (15,000 to 76,000 datagrams). The first attempt at
2,000 failed reproducibility on P2 and P4 for that reason.


## Why Docker

No passwordless root on the development machine, and AppArmor blocks
unprivileged user namespaces (`kernel.apparmor_restrict_unprivileged_userns=1`),
so `tc` cannot run directly. The user is in the `docker` group, and a container
with `NET_ADMIN` can shape its own interface.

## Profile definitions, made precise

SUCCESS.md gives one rate, RTT and loss per profile. Applied as follows, so the
numbers mean one thing:

- **Rate** is applied in both directions (netem `rate`).
- **RTT** is split evenly: half the delay on each end's egress.
- **Loss** is per direction: each end's egress drops that fraction. A ping, which
  crosses both directions, is lost at about twice the rate.
- **P4** toggles 100% loss on both ends: 30 s up, 60 s down.
- **P5** runs on a Docker network with `--internal`, so no route to the internet.

## Validation, per profile, run twice

- RTT: 100 pings, median, within ±10% of target.
- Delivered rate: UDP at 1.2 times the cap for 30 s; received rate within ±10% of
  cap × (1 − loss).
- Loss: UDP at half the cap, at least 2,000 datagrams; the target must fall
  inside the 95% binomial confidence interval of the measured loss.
- P4: 0.2 s probes over two cycles; up and down windows within ±10% of 30 s and
  60 s.
- P5: no route to a public address.
- Reproducibility: run 2 within ±10% of run 1 on every metric.

## Blocked: the WhatsApp baseline

Phones have to send their traffic through the shaped link. This laptop's only
Wi-Fi card carries its own internet connection and its Ethernet port has no
cable, so it cannot also be the phones' access point. Needed: a USB Wi-Fi
adapter that supports access-point mode, or a spare router, plus two phones with
WhatsApp. Grey's phone is in use for other testing (2026-09-21).

**2026-10-05: the hardware block is gone.** The Ethernet port has a cable and
an address on the home LAN (192.168.8.215/24, default route via 192.168.8.1),
and NetworkManager reports the Wi-Fi card can be an access point
(`nmcli -f WIFI-PROPERTIES device show wlp2s0`: `AP: yes`, 2.4/5/6 GHz). The
user may create a shared hotspot without root (`nmcli general permissions`:
`wifi.share.protected yes`). Still root-only: `tc` on the host interface, and
`tcpdump` (installed, no capabilities; `dumpcap` absent). `adb` and `scrcpy`
are installed; no phone attached. `iw` is still not installed and is not
needed. Open: which two phones carry WhatsApp for the measurement.

## WhatsApp baseline: instruments ready, 2026-10-05

`lab/baseline/` (README there is the procedure). Field phone, an Android with
mobile data off, on a hotspot this laptop hosts; the consultant phone, an
iPhone, on the home Wi-Fi, unshaped, as in the real scenario and so that a
peer-to-peer call cannot bypass the ingress shaping inside the Wi-Fi driver.
The laptop never needs access to the iPhone.

No root: `tc` and `tcpdump` run in `tremulator-lab:latest` on the host network
with `NET_ADMIN`. Proved on the unused `docker0` bridge before touching Wi-Fi:
netem write, `ifb0` creation, ingress `matchall`/`mirred` redirect, teardown.
Shaping numbers are the lab's exactly, on egress to the phone and on `ifb0`
for its uploads. Each step logs to `results/*.log` with a timestamp.

Instruments (`lab/tool/bin/baseline_*.dart`, 15 tests, seen to fail once):
`baseline_validate` (ping RTT, iperf3 rate and loss with the lab's checks and
sizing, `--ping-only` fallback, `--duty` for P4), `baseline_events` (operator
timestamps), `baseline_flows` (relay vs peer-to-peer from the capture),
`baseline_onsets` (one-way audio delay from a clap recording).

Pre-registered before the first run (README, "Pre-registered rules"): RTT
target = profile RTT + unshaped Wi-Fi RTT, tolerance max(10%, 2 ms); ping loss
is two-way, 1 − (1 − p)²; a failed validation is kept and the profile is not
measured until it passes.

Still needed: the two phones here, `iperf3` on the Android (Termux) or the Mac
on the hotspot for the rate check, and an afternoon. Unverified until then:
whether the phones stay on a Wi-Fi network with no internet for P5.

## WhatsApp baseline results, 2026-10-05/06

Field phone: OnePlus CPH2749 (Android 16) on the laptop's shaped hotspot,
mobile data off, home network forgotten. Consultant phone: iPhone on the home
Wi-Fi (P1–P4) or on the hotspot in airplane mode (P5, P0). Every call was
relayed through Meta (UDP 3478); the phone tried a direct path to the iPhone
on every call (20 packets out, none back). Raw records: `lab/baseline/results/`.

| Profile | Texts A→i | Texts i→A | Photo (1.1 MB in) | Voice call 3 min | One-way audio delay | Video call 3 min | Video frozen (Android side) |
|---|---|---|---|---|---|---|---|
| P1 rural 2G, 50 kbit/s, 400 ms, 5% | 10/10, median 5.3 s, max 7.7 s | 10/10 | 20.6 s | held, 9–22 kbit/s sent | **690–696 ms** (one pair, two detectors agree) | held, link saturated | 14.2 s/min (24.1, 7.8, 8.9) |
| P2 congested 3G, 300 kbit/s, 200 ms, 2% | 10/10, ≤4.9 s | 10/10 | 20.2 s | held (56 s, 4 min, 97 s calls) | unresolved: 258–268 ms by the amplitude detector, 520–530 ms by the transient detector, different onset pairs | held, 145/202 kbit/s | 3.4 s/min |
| P3 satellite, 1 Mbit/s, 700 ms, 1% | 10/10, median 5.7 s, max 8.3 s | 10/10 | 6.0 s | held | unmeasured: recording dominated by speech, no clean pair | held, 660 kbit/s up | 6.0 s/min (4.5, 6.2, 6.9) |
| P4 intermittent, 30 s up / 60 s down | 18/18; 3 s when up, 53–75 s when sent into an outage | 10/10, in bursts after outages | 86 s (sent 3 s into an outage) | **dropped ~25 s after the cut**, twice (51 s logged both) | — | **dropped ~28 s after the cut** (59 s logged) | — |
| P5 field LAN, no internet | clock icon, never sent (>11 min) | clock on the iPhone, none arrived | — | never rings; "Couldn't place call. Make sure your device has an internet connection" between 86 and 383 s; logged No answer | — | — | — |
| P0 dead link | clock, timed out at 60 s | — | — | stuck on "Calling", ended by hand at 57 s, logged No answer | — | — | — |

Validation on the Wi-Fi path (all pass under the pre-registered rules):
P1 RTT 442 ms vs 427, 44.9 kbit/s vs 45.6, loss 4.86% (CI 4.60–5.14);
P2 226 vs 227 ms, 266 kbit/s vs 282, loss 1.95% (1.84–2.06);
P3 728.5 vs 727 ms, 938 kbit/s vs 950, loss 1.008% (0.955–1.064);
P4 up 30.1 s, down 61.2 / 60.9 s. P5 RTT failed (26.0 ms vs 32.2 ± 3.2) because
the unshaped base RTT used was yesterday's 27.2 ms, against the rule's "same
session"; recorded as a fail, not reinterpreted.

Caveats: text and photo times have a 2.5 s read resolution (the screen poll);
the photo WhatsApp actually sent is much smaller than 1.1 MB, size unmeasured;
iPhone→Android latency is unmeasured (no send instant). Audio delay: two
detectors in `baseline_onsets.dart` (amplitude threshold; transient = energy
jump on the differenced signal, which removes the laptop microphone's DC
offset of about 6,900/32,767). They agree on P1 only. Next time the clap test
needs silence on both sides for 10 s around each clap; speech through the
Android's speaker made P3 unpairable and P2 ambiguous. Video freeze is the Android side only, by ffmpeg freezedetect over
the remote-video area. The call driver logs nothing after the dial on most
calls (open defect); setup times come from the capture instead.

## WhatsApp baseline sessions, 2026-10-05/06

Session log and numbers: `lab/baseline/results/` (jsonl per command, counters,
flows). Instrument findings that changed the method, each declared before
the next measurement:

- The phone leaves the shaped hotspot for the saved home network when Android
  judges the link poor (phone Wi-Fi log 2026-10-05 19:09:04, 2026-10-06
  10:27:40). Every run now aborts the moment the phone's address leaves
  10.42.0.x; the P1 video drop was Android's IP-reachability check timing out
  behind the 50 kbit/s queue, so ARP and DHCP now bypass the shaping
  (`shape.sh`, prio fast band), declared 2026-10-06 before P3.
- WhatsApp sends under one packet a second during silence. A quiet call looks
  like lost media in the capture; the operator talks throughout.
- Dart's `FileMode.append` is not O_APPEND: two processes on one log file
  overwrite each other. One file per command.
- The lab image's SQLite finding stands; nothing new there.

## 2026-09-21 incident: the lab disturbed Grey's network

Grey reported the laptop dropping off the network every few seconds while run 1
was going. Everything was stopped at 15:21:44. NetworkManager's log shows **no
Wi-Fi disconnect** during the tests (the only one, 15:02:47, was the laptop
going to sleep, before the first Docker command at 15:12:59), but it logged
**612 events** about Docker bridge and veth interfaces between 15:12:59 and
15:21:44: each profile created and removed a Docker network and two containers.
Applications that watch for network changes can treat that as a disconnect.
Grey, afterwards: the alerts came from the Linux network indicator, not from an
application, and **they stopped when the run stopped**. So the cause is the
Docker interface churn; the Wi-Fi connection itself never dropped.

Fixed in `validate.py`: two networks and two container pairs are created once
per run and reused, with only `tc` changing between profiles (from about 20
network changes per run to 2). The same fix went into `mutation_test.py` at
`936fcc5` (2026-09-21); the Dart runs d1 and d2 on 2026-09-22 ran on it.
Permanent fix on Grey's side, if he chooses: a NetworkManager
`unmanaged-devices` rule for `docker*`, `br-*` and `veth*`.

**Do not restart the network runs without Grey's go.**

## Findings that matter beyond Gate 1

- **Dart's bundled SQLite does not wipe on delete.** package:sqlite3 3.6.0
  bundles SQLite 3.53.4 with `secure_delete` off by default and no SECURE_DELETE
  compile option (`lab/tool/bin/sqlite_defaults.dart`). Debian's system SQLite
  has it on. A plain DELETE in a Dart app on the bundled build leaves the bytes.
  Gate 3 must check the real client's SQLite or SQLCipher build.

## Instrument defects found and fixed (each by measurement)

- iperf3's own setup crosses the shaped link: 0/40 errors at 0% loss, 20/29 at
  30%. Retried, with a fresh server, and retries recorded.
- One Ethernet segment means ARP fails during a P4 outage and ping exits;
  neighbour entries are pinned, as a routed WAN behaves.
- A hung connection on the dead link crashed the run; it is now a result.

## Findings so far

- iperf3 reports the sender's rate in `end.sum`; the receiver's is in
  `end.sum_received`. The first run read the wrong one (`run1-invalid-*`).
- Debian and this Docker image build SQLite with `SECURE_DELETE` on, so a plain
  DELETE zeroes freed pages. The first mutation run's purge defect was therefore
  never injected (`m1-invalid-*`). **Gate 3 must check the real client's SQLite
  or SQLCipher build**, not assume either default.
- The scanner initially missed partly-escaped JSON strings and base64 wrapping
  gzip; both fixed, both now in its tests.
