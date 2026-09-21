# Gate 1: build and validate the instruments

Started 2026-09-21. Criteria are in [SUCCESS.md](SUCCESS.md); this file says
how each is being met and what is blocked.

| Criterion | How | State |
|---|---|---|
| Five network profiles reproducible to ±10% | Docker lab: two containers with `NET_ADMIN`, `tc netem` on each end (`lab/network/`) | **paused** mid run 1: P1, P2, P3 passed every check, P4 RTT passed; P4 duty cycle, P5, P0 and run 2 not done |
| Instrument fails a 0 kbit/s link and passes P5 | same lab | not reached |
| Adversary harness: no plaintext in server storage or traffic | canary scanner over files and packet captures (`lab/adversary/`) | **done**: 13/13 encoding checks |
| Harness catches at least 5 injected defects | toy client/server with switchable defects | **done**: correct toy clean, 7/7 defects caught, twice (runs m2, m3) |
| WhatsApp baseline on all five profiles | two phones routed through the shaped link | **blocked: needs hardware** |

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

## 2026-09-21 incident: the lab disturbed Grey's network

Grey reported the laptop dropping off the network every few seconds while run 1
was going. Everything was stopped at 15:21:44. NetworkManager's log shows **no
Wi-Fi disconnect** during the tests (the only one, 15:02:47, was the laptop
going to sleep, before the first Docker command at 15:12:59), but it logged
**612 events** about Docker bridge and veth interfaces between 15:12:59 and
15:21:44: each profile created and removed a Docker network and two containers.
Applications that watch for network changes can treat that as a disconnect.
That link is a hypothesis, untested; whether the drops stopped after 15:22 is
Grey's to confirm.

**Fix before resuming:** create the lab networks once and reuse them, changing
only the `tc` settings between profiles. **Do not restart without Grey's go.**

## Findings so far

- iperf3 reports the sender's rate in `end.sum`; the receiver's is in
  `end.sum_received`. The first run read the wrong one (`run1-invalid-*`).
- Debian and this Docker image build SQLite with `SECURE_DELETE` on, so a plain
  DELETE zeroes freed pages. The first mutation run's purge defect was therefore
  never injected (`m1-invalid-*`). **Gate 3 must check the real client's SQLite
  or SQLCipher build**, not assume either default.
- The scanner initially missed partly-escaped JSON strings and base64 wrapping
  gzip; both fixed, both now in its tests.
