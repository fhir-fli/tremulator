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
