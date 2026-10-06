# WhatsApp baseline over a shaped Wi-Fi path

Gate 1's last criterion (SUCCESS.md): measure WhatsApp on P1–P5, and show
it fails on P0. The numbers become the targets for Gates 3–5. Nothing here
needs root: shaping and capture run in the lab image on the host network.

## Layout

| Role | Device | Network | Shaped | Recorded by |
|---|---|---|---|---|
| Field clinician | Android, USB to the laptop, **mobile data OFF** | laptop hotspot `tremulator` (10.42.0.0/24) | yes, both directions | `scrcpy --record` + the packet capture |
| Remote consultant | iPhone | home Wi-Fi through the router (192.168.8.0/24) | no | its own screen recording (Control Centre), sent over afterwards |

Only the field side is shaped, as in the real scenario. Keeping the iPhone off
the hotspot also stops a peer-to-peer call from passing station to station
inside the Wi-Fi driver, where the ingress half of the shaping would miss it.
The laptop needs no access to the iPhone. Every timing comes from the capture
on the laptop, the Android's screen recording, and the operator's event log.

Mobile data must be off on the Android for the whole session, or WhatsApp will
leave the shaped path the moment it degrades. Both phones: screen on, battery
saver off.

## Set up once per session

```bash
cd lab/baseline
./hotspot.sh up                 # prints the SSID and password; join with the Android
./hotspot.sh status             # the Android's address appears under "stations seen"
adb devices                     # the Android over USB
PHONE=10.42.0.23                # from status
dart run ../tool/bin/baseline_validate.dart --profile off --phone $PHONE --label s1
#   -> median unshaped Wi-Fi RTT; keep it as BASE
```

The laptop's own Wi-Fi client disconnects while the hotspot runs; internet
stays on the Ethernet cable. `./hotspot.sh down` at the end; the client
reconnects on its own.

## Per profile, in this order: P2, P1, P3, P4, then P5 and P0 last

P5 and P0 take the laptop offline (`./hotspot.sh offline`), so they go last.

```bash
./shape.sh P2                                   # P4: leave it looping in its own terminal
dart run ../tool/bin/baseline_validate.dart --profile P2 --phone $PHONE --label s1 --base-rtt $BASE
#   types two iperf3 commands for the phone (Termux: pkg install iperf3) or the Mac;
#   --ping-only if neither is available (RTT and loss only, rate unmeasured)
#   P4: --duty instead, 185 s of pings while the loop runs
./capture.sh p2                                 # own terminal, Ctrl-C at the end
scrcpy --record results/p2.mkv --no-playback    # own terminal
dart run ../tool/bin/baseline_events.dart p2    # own terminal: type events as they happen
```

Do not take a WhatsApp number on a profile whose validation did not pass;
fix the link first, and record the retry.

Tasks on each profile, both directions where there are two:

| Task | What to do | Numbers taken |
|---|---|---|
| T1 text | 10 messages each way, about 10 s apart, 20 words each | per message: tap-to-one-tick (server) and tap-to-two-ticks (delivered) from the Android recording; iPhone→Android: `sent n` in the event log to appearance on the Android screen |
| T2 photo | one fixed photo each way (the same file every time; WhatsApp recompresses, so record the file it shows) | time to delivered |
| T3 voice call | Android calls the iPhone, 3 min; log `dial`, `ringing`, `connected`, `dropped`, `hangup` | setup time = dial→connected; survives 3 min yes/no; relay or peer-to-peer from the capture; one-way delay from the clap test, twice |
| T4 video call | 3 min, both cameras on | freeze seconds per minute on each side (below); relay or peer-to-peer |
| P4 only | run T1 across two full 30/60 cycles and start T3 in an up window so it crosses an outage | messages that never arrive; whether the call survives 60 s dark and how long to recover |
| P5, P0 | attempt T1 and T3 | expected: nothing goes through; record what WhatsApp shows and after how long |

After each profile:

```bash
dart run ../tool/bin/baseline_flows.dart results/p2.pcap --phone $PHONE   # relay vs peer-to-peer
ffmpeg -i results/p2.mkv -vf "crop=W:H:X:Y,freezedetect=n=-60dB:d=0.5" -f null - 2> results/p2.freeze.txt
#   crop to the remote video area; freeze_start/freeze_end lines give the frozen seconds
./shape.sh off
```

Clap test (`audio_delay.sh p2-clap 20` then `baseline_onsets.dart`): both
phones in the room, the Android on loudspeaker, one sharp click near the
iPhone. The laptop microphone hears it directly, then from the Android's
speaker; the gap is the one-way delay to within about 10 ms. WhatsApp's noise
suppression may swallow a clap: a short loud "pa" works.

## Pre-registered rules, 2026-10-05, before the first run

- Shaping numbers are the Docker lab's exactly (GATE1.md): half the RTT and
  the full loss on each direction, the rate cap on both, netem's default queue.
- **Declared 2026-10-06, after P1's video call and before any further
  measurement:** ARP and DHCP bypass the shaping in a fast band of a prio
  qdisc; all other traffic, pings included, is shaped as before. A cellular
  link has no gateway to probe; on the shaped hotspot Android declared the
  laptop unreachable under 50 kbit/s video load, re-DHCPed, gave up and left
  for the home Wi-Fi mid-call. P1 video is rerun under this rule; nothing
  measured before it is reinterpreted.
- RTT target on Wi-Fi is the profile's RTT plus the unshaped Wi-Fi RTT to the
  same phone measured the same session; tolerance is the larger of 10% and
  2 ms, because P5's 5 ms would otherwise be judged on 0.5 ms of Wi-Fi jitter.
- Loss by `--ping-only` is two-way, target 1 − (1 − p)², Wilson 95% interval,
  sized like the lab's loss tests. Pooled judgement across profiles as the lab
  declared on 2026-09-22.
- Event-log timings carry about 0.3 s of human reaction; where the screen
  recording or the capture gives the same instant, that is the number used.
- A profile whose validation fails is not measured until it passes; the failed
  validation stays in the results file.

## What lands where

`results/validate_<label>.jsonl`, `events_<label>.jsonl`, `<pcap>.flows.json`,
`shape.log`, `hotspot.log`, `capture.log`, `audio.log` are committed. The raw
`.pcap`, `.wav` and screen recordings are not (`.gitignore`); they stay on
this laptop. The password in `results/hotspot.pw` is never committed.
