# Gate 2 step 4 plan: voice and video calls

Written 2026-10-07. Grey's go 2026-10-10 ("we can give it a try, go for
it").

## Progress

- **Step 1 done 2026-10-10.** `packages/tremulator_calls`, with the
  integration tests in its `example/` Linux app, run on a private Xvfb
  (`lab/tool/xvfb.sh`, no root). Two phones, a real in-process fhirant, the
  real plugin: a call set up through the mailbox connects over loopback and
  hangs up; a fingerprint with one hex digit changed reaches "connecting",
  then "failed", never "connected". Negative control: with the fingerprint
  left alone the second test fails (the call connects). 5 of 5 runs green.
- flutter_webrtc is **1.6.2+hotfix.4**, not 1.6.2: 1.6.2's Linux app
  segfaulted at start, 3 of 3 (null audio device, `flutter_media_stream.cc`
  line 34). Hotfix 4 also moves libwebrtc 7871.01 → 7871.03; which change
  fixed it is unknown. Hotfix 4 also fixes a Linux data-channel threading
  race (#2194), which the control channel would hit.
- The call tests use a data channel only, no microphone or screen: media
  comes in step 2 inside Docker. strace of the app's start shows no access
  to the laptop's sound server; not checked during a call.
- Client: `Incoming.label` and `Client.sendCall`, so call setup never reaches
  the chat. The in-process test server is now one package,
  `tremulator_test_server` (was two identical copies).
- **Step 2 done 2026-10-10 (calls5).** `app/` lab mode in Docker
  (`lab/gate2/calls.py`, `Dockerfile.calls`, Ubuntu 24.04, one network
  `tremulator-g2c-ext`), no shaping, 30 s call: connected in 453 ms
  host to host; Bob decoded 850 frames, the stats' freeze count 0; ~1,420
  audio packets each way. Bob's screen recording shows the test pattern
  (stills in `results/calls5/none/`). Frozen video by Gate 1's freezedetect
  (n=-60dB, d=0.5) between connected and ended: Bob 0.13 s (one span, the
  gap before the first frame), Alice's own screen 0. The DTLS fingerprints
  of both phones: 0 hits in the server's dump, store and capture; 2 hits in
  the positive control (Alice's log).
- calls1–3 are invalid, each for an instrument defect, named in
  `results/INVALID-RUNS.md`. The text lab was re-proved after its helpers
  moved to `labkit.py`: run9, P2, 10/10, median 870 ms, canary clean.
- Recordings stay on disk only (Grey 2026-10-16): a 3-minute call records
  Alice's screen at ~105 MB (17 MB per 30 s in calls5), over GitHub's
  100 MiB file limit. `.gitignore` keeps `*.mp4`, `*.mkv`, `*.wav` under
  `lab/gate2/results/` out; the numbers taken from them are committed.
- **Step 3 pieces written 2026-10-16, not yet run** (each Docker run needs
  Grey's go):
  - P5 runs on a second network created `--internal`, its own server,
    relay and phones, as `run.py` does.
  - A relay (coturn 4.6.1, the phone image with no screen) per network,
    fresh per profile, shaped like the server; both phones always get it.
    `<profile>-blocked` blackholes the phones' route to each other (proved
    by a TCP probe: refused before, not refused after), so the call must
    use the relay. Relayed or not: the call's own stats and the count of
    successful allocations in the relay's log.
  - Voice delay: a click track (30 ms tone, one per 10 s) into Alice's
    microphone once her call connects; Alice's microphone and Bob's
    speaker recorded with the wall-clock stamp of ffmpeg's PulseAudio
    input; onsets by Gate 1's detector; `lab/gate2/voice_delay.py`. Its
    offline self-check reads a known 300 ms and 3 of 9 clicks lost exactly;
    swapped files pair nothing. Untested: whether the stamp in the
    container is the wall clock. `plus500` (500 ms one way, nothing else)
    is the in-lab check: it must read ~500 ms more than `none`.
- calls6 invalid (three lab defects, `results/INVALID-RUNS.md`).
- **calls7 (2026-10-16), 30 s each, 2 clicks per call:**

  ⚠️ 2026-10-17: the voice-delay medians in the calls7 and calls8 tables
  below carry an unknown per-call offset of up to about 0.7 s (recording
  start stamps, `lab/gate2/results/INVALID-RUNS.md`); fixed, not yet
  re-measured.

  | Profile | Route | Connect (Alice) | Bob frames | Frozen s/min | Voice delay median (range) |
  |---|---|---|---|---|---|
  | none | direct | 485 ms | 806 | 0.21 | 109 ms (88–129) |
  | none-blocked | relay | 567 ms | 756 | 0.24 | 112 ms (107–117) |
  | plus500 | direct | 13.4 s | 778 | 1.88 | 651 ms (651) |
  | P5 | direct | 679 ms | 763 | 0.33 | 115 ms (99–132) |

  Instrument check: plus500 reads 542 ms more than none, against 500 ms
  added; 2 clicks each, so n is small. ~110 ms is the floor of the lab
  with no shaping (pulse buffers, jitter buffer, codec). Video arrives at
  960x540 in every profile. The pattern was on top at connect in all
  four; Alice's own screen 0 s frozen in all four. Fingerprints 0 server
  hits, 2 in the control, every profile. plus500's 13.4 s connect is
  setup through the mailbox at 1 s round trip, not media.
- **calls8 (2026-10-16), the 3-minute sweep, Grey's go.** Recomputed with
  the fixed timing (`--reanalyse`; frozen video from connect to the first
  hang-up of either phone). 17 clicks sent per call.

  | Profile | Route | Connect | Call | Frozen s/min | Voice median (range), heard | WhatsApp (GATE1.md) |
  |---|---|---|---|---|---|---|
  | P1 | direct | 19.5 s | held 3 min | 55.6 | 663 ms, 1 of 17 | frozen 14.2; voice 690–696 ms |
  | P1-blocked | relay | 23.7 s | **dropped at 17 s** | — | 0 of 17 | relayed every time |
  | P2 | direct | 5.1 s | held | 0.07 | 428 (273–458), 17 | frozen 3.4; voice unresolved |
  | P2-blocked | relay | 5.7 s | held | 1.67 | 519 (392–574), 17 | |
  | P3 | direct | 12.0 s | held | 0.79 | 688 (545–776), 17 | frozen 6.0 |
  | P3-blocked | relay | 13.5 s | held | 6.12 | 1,047 (835–1,170), 17 | |
  | P4 | direct | 6.3 s | **dropped at the first outage, 22 s** | — | 0 of 17 | dies ~25 s after the cut |
  | P4-blocked | relay | 8.3 s | **dropped at the first outage, 19 s** | — | 0 of 17 | |
  | P0 | — | not placed: Bob cannot reach the server (known negative) | | | | |

  Fingerprints: 0 server hits, 2 in the control, every call. Findings:
  1. No call recovers from a lost link: three of eight dropped, each ~10 s
     after the link went, and nothing reconnects. First thing to build (E8).
  2. P1 with video carries almost no sound: 41% of Bob's audio packets
     lost, video 164 frames. E7 (video gives way to audio) is the fix.
  3. The hang-up travels through the mailbox: on P1 Bob learned of it 61 s
     late.
  4. Unknown: the lab shapes the relay like a phone, so a relayed packet
     crosses two slow links; a deployed relay sits on the server's link.
     The relayed rows may be worse than the field. Not yet checked.
  5. Unknown: on P4 direct the first click was due ~5 s before the cut and
     was not heard.
  6. (2026-10-17) P4-blocked and P0 ran with P4's on/off loop still going
     (INVALID-RUNS.md, shaping never cleared).
- **Reconnection (E8), built 2026-10-17 (`e539ea1`).** A connected call that
  loses its link restarts the connection through the mailbox and waits up to
  90 s. 300 s calls; both phones' links cut 30 s after connecting (server
  and relay keep theirs). Before the change (calls9-before) every cut, even
  20 s, ended the call "failed" 16 s after the link went. "Back" is from
  each phone noticing the loss (6-9 s after the cut) to reconnected.

  | Profile | Route | Call | Back (Alice / Bob) | Restarts sent (failed) | Clicks after the cut | First click after the link returned | Voice after | Bob frozen s/min |
  |---|---|---|---|---|---|---|---|---|
  | cut20 | direct | held | 11.7 / 11.8 s | 1 (0) | 24 of 24 | 5.5 s | 254 ms | 4.86 |
  | cut20-blocked | relay | held | 11.9 / 11.9 s | 1 (0) | 24 of 24 | 5.7 s | 342 ms | 4.57 |
  | cut60 | direct | held | 52.6 / 53.1 s | 2 (1) | 20 of 20 | 5.8 s | 216 ms | 12.66 |
  | cut60-blocked | relay | held | 65.3 / 65.5 s | 2 (1) | 19 of 20 | 15.5 s | 278 ms | 15.26 |
  | cut120 | direct | ended `lost` on both, 90 s after noticing, 0.35 s apart | — | 3 (3) | — | — | — | — |
  | cut120-blocked | relay | ended `lost` on both, 0.09 s apart | — | 2 (2) | — | — | — | — |
  | P4 | direct | **never connected**: the link went during setup | — | — | — | — | — | — |
  | P4-blocked | relay | **never connected**: same | — | — | — | — | — | — |
  | P1-blocked | relay | held 300 s (calls8: dropped at 17 s); lost twice, back both times | 6.6 and 79.7 / 55.5 s | 3 (2) | 2 of 29 clicks heard in the whole call | — | 845 ms | 59.81 |

  Instrument checks in the same build (calls9): `none` 103 ms (65–227),
  29 of 29; `plus500` 847 ms (605–1,060), 29 of 29, so +744 ms for +500 ms
  added. Across two containers the voice clock agrees to 0-1 ms (one trial
  64 ms; `cross_stamp_check.py`), so the extra 244 ms is the call, not the
  instrument. Fingerprints 0 server hits, 2 in the control, every call.
  Findings:
  1. A link lost mid-call now recovers, up to 60 s cut, direct and relayed;
     past the 90 s grace both phones end it alike.
  2. A link lost DURING setup still ends the call: the answer (P4) or its
     delivery (P4-blocked) falls in the outage, the setup message is sent
     once and never retried, and a connection that never connected ends as
     `failed`, the rule that catches a wrong fingerprint. Next to build.
  3. Voice delay after a cut stays higher than before it (216-342 ms
     against 103 ms on an uncut call); unexplained.
  4. P1 relayed now survives but carries 2 of 29 clicks: video starves the
     audio (E7).
  5. A mailbox send can time out on the sender yet reach the server (P1:
     Bob answered a restart Alice logged as failed); the offer numbers kept
     the stale answer out.
  6. The lab app exits with an error when its last mailbox fetch after the
     call fails in the outage (cut120: exit 2 on both); the call result is
     unaffected. Lab harness, to fix.


### Setup during an outage (calls12-15, 2026-10-18)

Plan approved by Grey 2026-10-17. Build `df2cca8` for calls12-13, `d3248a1`
(adds the hang-up retry) for calls14-15. Changes: an offer or answer whose
send fails is sent again every 2 s; a call that has not connected keeps
trying for 90 s; a never-connected failure ends the call at once only when
the transport's `dtlsState` is `failed` (a refused certificate), otherwise it
restarts as a lost call does; a failed collect after a wake-up is retried
every 2 s; the mailbox hang-up is retried for up to 90 s. `offercut60` and
`answercut60` cut both phones' links for 60 s the moment Alice places the
call or Bob receives her offer. 300 s calls. 21 valid calls; calls13
offercut60-blocked is invalid (INVALID-RUNS.md). Rows from
`lab/gate2/setup_table.py calls12 calls13 calls14 calls15`
(`results/setup-table.jsonl`). "Never-connected failures" gives the phone,
the reading (route or handshake) and the DTLS states.

| Profile | Run | Route | Placed → connected | Link back → connected | Sends repeated (Alice / Bob) | Never-connected failures | Ended (Alice / Bob) | Clicks heard | Bob frozen s/min |
|---|---|---|---|---|---|---|---|---|---|
| P4 | calls12 | host→host | 6.9 s | — | 14 / 0 | — | hangup / lost | 9/29 | 45.54 |
| P4 | calls13 | host→host | 69.5 s | — | 7 / 5 | alice route (new) | hangup / remote-hangup | 8/29 | 42.22 |
| P4 | calls14 | host→host | 6.8 s | — | 13 / 0 | — | hangup / remote-hangup | 9/29 | 48.7 |
| P4 | calls15 | host→host | 69.5 s | — | 9 / 0 | — | hangup / remote-hangup | 10/29 | 43.02 |
| P4-blocked | calls12 | host→relay | 7.9 s | — | 14 / 0 | — | hangup / lost | 9/29 | 46.8 |
| P4-blocked | calls13 | host→relay | 7.1 s | — | 6 / 0 | — | hangup / lost | 8/29 | 48.63 |
| P4-blocked | calls14 | host→relay | 72.7 s | — | 17 / 0 | alice route (new), alice route (new), bob route (connecting) | hangup / remote-hangup | 9/29 | 43.72 |
| P4-blocked | calls15 | host→relay | 8.4 s | — | 10 / 0 | — | hangup / remote-hangup | 7/29 | 49.23 |
| offercut60 | calls12 | host→host | 63.3 s | 3.2 s | 6 / 0 | — | hangup / remote-hangup | 29/29 | 0.49 |
| offercut60 | calls13 | host→host | 60.5 s | 0.4 s | 5 / 0 | — | hangup / remote-hangup | 29/29 | 2.77 |
| offercut60 | calls14 | host→host | 64.7 s | 4.6 s | 3 / 0 | — | hangup / remote-hangup | 28/29 | 10.34 |
| offercut60 | calls15 | host→host | 63.2 s | 3.2 s | 5 / 0 | — | hangup / remote-hangup | 29/29 | 8.25 |
| offercut60-blocked | calls12 | host→relay | 63.3 s | 3.2 s | 6 / 0 | — | hangup / remote-hangup | 28/29 | 7.45 |
| offercut60-blocked | calls14 | host→relay | 63.6 s | 3.5 s | 1 / 0 | — | hangup / remote-hangup | 29/29 | 0.03 |
| offercut60-blocked | calls15 | host→relay | 61.3 s | 1.3 s | 4 / 0 | — | hangup / remote-hangup | 27/29 | 6.39 |
| answercut60 | calls12 | host→host | 60.8 s | 0.4 s | 0 / 2 | bob route (new) | hangup / remote-hangup | 29/29 | 3.62 |
| answercut60 | calls14 | host→host | 62.7 s | 2.3 s | 0 / 5 | bob route (new) | hangup / remote-hangup | 28/29 | 13.32 |
| answercut60 | calls15 | host→host | 61.6 s | 0.9 s | 0 / 3 | bob route (new) | hangup / remote-hangup | 29/29 | 10.06 |
| answercut60-blocked | calls12 | relay→host | 69.7 s | 3.2 s | 0 / 4 | bob route (new) | hangup / remote-hangup | 29/29 | 5.03 |
| answercut60-blocked | calls14 | relay→host | 61.8 s | 1.3 s | 0 / 3 | bob route (new) | hangup / remote-hangup | 29/29 | 4.77 |
| answercut60-blocked | calls15 | relay→host | 62.3 s | 1.9 s | 0 / 6 | bob route (new) | hangup / remote-hangup | 29/29 | 8.35 |

Findings:
1. 21 of 21 connected. calls11 P4 and P4-blocked: 0 of 2.
2. A setup cut by a 60 s outage connects 0.4-4.6 s after the link returns,
   direct or relayed, offer or answer side.
3. P4's outage clock is not tied to the call: four of eight P4 calls set up
   in a link window (7-8 s), four ran into an outage (69.5-72.7 s). All
   connected and held 300 s, 7-10 of 29 clicks heard (the link is up a
   third of the time).
4. Every never-connected failure (9, on both phones) read as route, DTLS
   `new` or `connecting`, and the call went on to connect. The refused
   certificate reads `failed` (calls_test). The ICE state events could not
   tell the two apart: with a refused certificate the plugin reported the
   connection failed while its last ICE event said "checking".
5. The hang-up fell in an outage on P4 and Bob ended `lost` about 70 s late
   in 3 of 4 calls on the old build; 4 of 4 `remote-hangup` with the retry
   (calls14 P4: sent on attempt 7, 25 s after the first).
6. Fingerprints 0 server hits, 2 in the control, every call. Both apps exit
   0 every call (calls10-11 cut120: exit 2, a close() defect, fixed).
7. Open: Bob's frozen video after a setup cut ranges 0.03-13.3 s/min with no
   pattern by profile; three or four runs each cannot say why.
8. Open: Alice's container stalled ~13 s in calls13 (the run that stopped);
   cause unknown, host load was not recorded.

## Endpoints the calls must meet (Grey 2026-10-16: "as thorough and as robust as possible")

Each is a pass or fail that someone other than us defined, or a defect we
plant on purpose. Order is the build order; none started yet.

| # | Test | Passes when | Who defines it |
|---|---|---|---|
| E1 | A browser calls the app | Chrome (headless, in the lab) and the Linux app connect; each shows and plays the other's test picture and clicks; the identity check holds | Chrome's WebRTC, the shipped reference |
| E2 | Encryption known answers | the MLS working group's published test vectors pass through `tremulator_keys` (as far as the Dart `openmls` package exposes the steps; what it does not expose is listed, not skipped silently) | mlswg/mls-implementations `test-vectors.md` |
| E3 | Planted defects, each must turn a test red | (a) identity check off: a swapped fingerprint connects, test fails; (b) call setup sent unencrypted: the canary scan finds it on the server; (c) a server that swaps the offer: call refused; (d) relay given wrong credentials: no relayed call, and the app says so; (e) Bob answers a call from a device not in the conversation: refused | us, from the threat model; each defect named before it is planted |
| E4 | The relay sees only encrypted media | a capture at the relay holds no click-track audio and no fingerprint; positive control: the same scan finds the click in Alice's microphone recording | the adversary harness |
| E5 | The WhatsApp numbers | connect time, relayed share, voice delay, frozen video, survival across P4's drop, per profile, against `GATE1.md` | Gate 1 measurements |
| E6 | Completion rate | 50 calls on P1 (Gate 4), completion at or above WhatsApp's on P1 | `SUCCESS.md` Gate 4 |
| E7 | Video falls back to audio | on P1 with video on, the call keeps sound and says video is off, rather than freezing | `SUCCESS.md` Gate 5, `DESIGN.md` |
| E8 | Failure modes | network lost mid-call then back (call resumes or ends cleanly, both sides agree); far phone killed mid-call; relay down at call start | `SUCCESS.md` standing categories |

Unknown until looked at: how much of the MLS key schedule the Dart
`openmls` package exposes (its source was not in the local package cache
on 2026-10-16); whether a lab bridge between Chrome and our mailbox needs
anything in the app beyond the existing signal format.


## What gets built, and kept (D16)

| Where | What it does |
|---|---|
| `packages/tremulator_calls` | Starts, answers and ends a call between two phones with `flutter_webrtc` 1.6.2 (MIT). The connection details each phone sends the other (the "offer" and "answer") travel as ordinary encrypted mailbox messages labelled `call`, so the server never sees them. Reads the call's own statistics. |
| `app/` | The first Flutter app: pick a colleague, text, call. Built for Linux desktop first (it runs in the lab) and Android second (the OnePlus). No polish. |
| `lab/gate2/calls.py` | The lab run for calls, same shape as `run.py`. |
| `lab/gate2/Dockerfile.calls` | The app's Linux build, a virtual screen, a virtual sound card, and coturn. |

Why the identity check works: each phone's connection details carry the
fingerprint of the certificate it will present, and WebRTC refuses a
connection whose certificate does not match (RFC 8122 section 6.2, read
2026-10-06: "MUST terminate the media connection with a bad_certificate
error"). Because the details travel inside the encrypted chat, a dishonest
server cannot swap them.

## How the lab feeds a camera and a microphone that do not exist

Read from the flutter_webrtc 1.6.2 source, 2026-10-07: on Linux it opens
cameras through the kernel's video devices (`flutter_media_stream.cc`, it
counts devices and opens one by name) and has no fake camera. Its feature
table lists Linux screen capture.

- **Picture: screen capture of a virtual screen.** Each container runs a
  virtual X screen (Xvfb, as on Grey's machines: never his live desktop). A
  test video plays on the sender's screen and the app shares that screen.
  This needs nothing on the laptop itself. Rejected: a loopback camera
  (v4l2loopback), which is a kernel module on Grey's laptop.
  Caveat, unmeasured: WebRTC may encode screen content differently from
  camera content (sharper, lower frame rate). If it does, the freeze numbers
  are not comparable to WhatsApp's camera call, and the loopback camera
  becomes Grey's decision.
- **Sound: a virtual sound card** (PulseAudio with a null sink) in each
  container. A click track plays into the sender; the receiver's output is
  recorded.

## What gets measured, with the same instruments as Gate 1

| Measure | How | Gate 1 WhatsApp number |
|---|---|---|
| connect time | from "call" pressed to media flowing, from the app's own log | from the capture |
| direct or relayed | the connected pair in the call statistics; then again with direct traffic blocked between the two phones, so the relay is forced | relayed every time |
| one-way voice delay | click track in, recording out, the Gate 1 transient detector (`baseline_onsets.dart`), 10 s of silence around each click | P1 690–696 ms, P2 unresolved |
| frozen video, seconds per minute | screen recording of the receiver, ffmpeg freezedetect, as Gate 1 | P2 3.4, P3 6.0, P1 14.2 |
| call survives the outage | 3-minute call across P4's 60 s drop | dies about 25 s after the cut |
| audio when video cannot | P1, video on: does the call fall back to audio or freeze | — |

SUCCESS.md asks for video freeze at five bandwidth caps but does not name
them. Proposed, my choice: 50 (P1), 150, 300 (P2), 600 and 1,000 (P3) kbit/s.

## Order, each with its proof

1. **Calls package, laptop only.** Two peers in one test process connect
   over loopback with the offer and answer passed through the real mailbox
   against an in-process fhirant. Proof: connected, and a changed
   fingerprint is refused (the test edits one character and expects failure).
2. **The Linux app in Docker,** headless, one call on an unshaped link.
   Proof: a recording shows the test video arriving.
3. **Profiles.** P1–P5 and P0, then the forced-relay pass, then the caps.
4. **Android:** the app on the OnePlus against the laptop, on the shaped
   hotspot, as Gate 1.

## Unknown until tried

- whether the flutter_webrtc Linux build runs under Xvfb in a container;
- whether its statistics carry the standard freeze counters; if not, the
  ffmpeg recording is the instrument, as in Gate 1;
- whether screen content encodes like camera content (above);
- whether `app/` needs the iPhone's push setup before it builds for iOS; not
  needed until step 7.

Every lab run creates two Docker networks, as before.
