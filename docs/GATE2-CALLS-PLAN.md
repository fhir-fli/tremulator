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
