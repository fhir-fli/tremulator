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

E1 PASSED 2026-11-19 (calls51, `lab/gate2/calls_e1.sh`, rule in `e1_check.py`): 8 of 8. Chrome for Testing 158.0.8127.36 running the app's web build, in a lab phone with a screen (not headless). Chrome as Bob / as Alice / Linux both ends, voice median ms on open, P2, P2 relayed: 132, 280, 366 / 72, 251, 391 / 54, 243, 325; every call connected, picture and 10-11 of 11 clicks through. A planted wrong certificate is refused both ways: no sound or picture through, both phones end as failed. The run found and fixed: a refused certificate left the other phone waiting 90 s as if the line dropped (app fix, RFC 8842 sections 3.1 and 6); three lab defects (`results/INVALID-RUNS.md`). Open: Chrome still sends 66-81 packets per call to Google (`outside_pkts`); the new two-phone certificate test failed on the code before the fix (Bob's call never ended, 5 s) and passes after it; whole call suite 18/18 on 2026-11-20 through `lab/tool/call_tests.sh`, which keeps the test window off the desktop (before it, the Wayland session's GDK_BACKEND put the window on the live desktop, where it took the mouse, and four screen-capture tests failed capturing the empty virtual screen).
| E2 | Encryption known answers | the MLS working group's published test vectors pass through `tremulator_keys` (as far as the Dart `openmls` package exposes the steps; what it does not expose is listed, not skipped silently) | mlswg/mls-implementations `test-vectors.md` |
E2 PASSED 2026-11-20 (`lab/e2/RESULTS.md`): the working group's 16 vector files (commit 2034fe72) pass through our own MLS reading code (10 Dart tests, about 3,800 entries) and through openmls 0.9.0's own known-answer tests with the current files swapped in (15 of 15); every check was seen to fail on a damaged copy. Limits: openmls checks suites 1-3 only (the app uses 1); five checks the vector document asks for are not made by openmls's tests (listed in RESULTS.md); joining from a given welcome cannot be tested from Dart, since the library will not load outside private keys.
| E3 | Planted defects, each must turn a test red | (a) identity check off: a swapped fingerprint connects, test fails; (b) call setup sent unencrypted: the canary scan finds it on the server; (c) a server that swaps the offer: call refused; (d) relay given wrong credentials: no relayed call, and the app says so; (e) Bob answers a call from a device not in the conversation: refused | us, from the threat model; each defect named before it is planted |
E3 PASSED 2026-11-21 (`lab/e3/RESULTS.md`): every planted defect turned its test red and every test was green without it: (a) 2 of 3 fingerprint tests red, the third green because WebRTC itself refuses the wrong certificate; (b) the lab found Alice's fingerprint 94 times in the server's capture, 0 without the plant, and fhirant refused to store the plain-text setup (422); (c, e) 6 of 6 swap and outsider tests red; (d) with the real relay and a wrong password the call never connects and the caller says the relay was unavailable. Found and fixed on the way: the lab's fingerprint hunt was blind on calls that never connected; the first relay warning fired falsely on the answering phone (it gathers no relay address on an open network); `answer()` threw when a call ended during gathering. Open: the mailbox's reported sender is not checked against the encrypted sender (matters once a conversation has more than two members). Calls suite 21/21.
E3 PLAN, 2026-11-21, approved by Grey ("ok, go"). Each defect is planted as a patch in a
throwaway copy of the code (`git worktree`, as E1's before-the-fix run), never as a
switch in the shipped app. Each test is run on the plant (must go red) and on main
(must go green). Patches and runs in `lab/e3/`.
- (a) Our own check that a later setup keeps the same certificate fingerprint
  (`calls.dart` `_applyRemote`) removed. Red: the two restart-fingerprint tests in
  `calls_test.dart`. Also recorded: the first-setup fingerprint test should stay
  green, because WebRTC itself refuses the wrong certificate (RFC 8122 section
  6.2); that check is not ours to switch off.
- (b) Call setup sent as plain text instead of encrypted (`client.dart`
  `sendCall`). Red: the lab's canary scan (`calls.py`) finds the certificate
  fingerprints on the server, today 0 hits; and `client_test` "call setup arrives
  labelled as a call".
- (c) New: a dishonest test server that swaps a call message for (1) an earlier
  call message replayed, (2) one from another conversation, (3) garbled bytes.
  Passes when no call rings and the phone reports the message as refused. Red with
  (b) planted: the swapped plain-text offer rings.
- (d) New: relay-only call with a wrong relay password. Passes when the call does
  not connect and the app reports "no route through the relay". Needs new app
  code: the plugin (webrtc_interface 1.5.1) has no relay-error event, so the app
  checks that a relay was set but no relay address came back. It cannot tell a
  wrong password from a relay that cannot be reached. Red: run before the new code.
- (e) New: Carol, not a member, sends Bob a call message carrying the
  conversation's id. Passes when Bob does not ring. Plant: a call message that
  fails to decrypt is read as plain text. Open, to look at: the mailbox's "from"
  is not compared with the sender inside the encrypted message.
| E4 | The relay sees only encrypted media | a capture at the relay holds no click-track audio and no fingerprint; positive control: the same scan finds the click in Alice's microphone recording | the adversary harness |
E4 PASSED 2026-11-21 (`lab/e4/RESULTS.md`): two calls through the relay, Bob heard 5 of 5 clicks in each; the relay's capture decoded to 0 clicks in every stream while the same scan found 9 of 9 in plain Opus sent the same way; 0 of 2 fingerprints at the relay; DTLS 1.3, so no certificate readable there. Not checked: the certificate reader on a DTLS 1.2 handshake; Bob's clicks at Alice; the video picture.
E4 PLAN, 2026-11-21, approved by Grey ("yes"); caller swap replaced by clicks on both microphones. Files: `lab/e4/` (new) and one option in `lab/gate2/calls.py`.
- Calls: direct route blocked (`none-blocked`, so every packet goes through the relay), right password, 60 s, click track on Alice's microphone as in E1. Two calls, Alice calling and Bob calling. The relay container captures every packet whole (new `--relay-capture`; today only the phones capture, and only headers).
- Sound scan (`lab/e4/relay_scan.py`): take every media packet out of the relay's capture (unwrapping the relay's own framing, RFC 8656 section 12), put the sound stream back together as Opus and decode it with ffmpeg, then look for the clicks with the same detector the voice-delay measure uses (`voice_delay.onsets`). Passes when 0 clicks are found.
- Positive control, the same scan: the same click track encoded as Opus and sent as plain, unencrypted media packets on the lab network, captured the same way. Must find the clicks (at least 9 in 10). If it cannot, a pass above means nothing. The plan's earlier control (Alice's microphone recording) is a sound file, not a capture, so it would test the detector but not the scan.
- Fingerprint: both phones' fingerprints hunted in the capture and the relay's log (`canary_scan.py`, as the server hunt). Passes when 0 found, with the phones' logs as the control.
- Measured, not a pass/fail: whether the relay can see each phone's certificate itself. In DTLS 1.2 the certificate crosses in the clear (RFC 6347), and its hash is the fingerprint; in DTLS 1.3 it is encrypted (RFC 9147). The scan takes any certificate out of the handshakes and hashes it. If the relay can see them, it can tell which phones are talking, though not what they say. Reported either way.
- Not covered: the video. It is encrypted the same way, but there is no detector for the test picture inside a capture.
| E5 | The WhatsApp numbers | connect time, relayed share, voice delay, frozen video, survival across P4's drop, per profile, against `GATE1.md` | Gate 1 measurements |
E5 DONE 2026-11-21, NOT MET (`lab/e5/RESULTS.md`): fails frozen video on P1, P2 and P3-relayed, and voice on P1 (11.6 s direct, 17.2 s relayed, against 690 ms); passes P3-direct frozen (4.29 vs 6.0), P4 survival 3 of 3, P5 3 of 3, P0 by the amended rule (Alice cannot register; no call placed). Connect time has no WhatsApp number.
E5 PLAN, 2026-11-21, approved by Grey ("yes"). The rules below are fixed before any run; a result is reported against them, never the rule moved to fit.
- Calls: the shipped defaults, Linux app both ends in the lab, 3-minute calls with video, click track and test picture as in every lab call. Three calls per profile: P1, P2, P3, P4, P5, P0, and P1, P2, P3 again with the direct route blocked (forced through the relay). 27 calls, about 2.5 hours, one lab run in the background (`lab/e5/run.sh`).
- WhatsApp's connect time is not in GATE1.md's table. It is derived first, from the Gate 1 files already on disk: the tap time in each `android_p*_call.jsonl` to the first media packet to Meta's relay (UDP 3478) in `p*.pcap`. If a call's pair cannot be read, that profile's WhatsApp connect time is "unknown", not guessed.
- Pass, per profile, where WhatsApp has a number:
  - connect time: our median at or under WhatsApp's;
  - one-way voice delay: our median at or under WhatsApp's (P1 690-696 ms; P2 and P3 have no WhatsApp number, so ours is reported, no pass or fail);
  - frozen video, seconds per minute on the receiving phone, same freezedetect: our median at or under WhatsApp's (P1 14.2, P2 3.4, P3 6.0);
  - P4: the call is still up after the 60 s drop and carries sound again after it (WhatsApp dropped 25-28 s after the cut, both tries);
  - P5 (no internet): the call connects (WhatsApp never rang);
  - P0 (dead link): the call ends as failed within the 90 s setup deadline, both phones agree, nothing hangs.
- Relayed share: reported per profile (WhatsApp relayed every call); no pass or fail, since going direct when possible is the design.
- Every number comes from the run's own files (calls.py summaries); the table is built by a script, not by hand.
- Before any run, 2026-11-21 (said to Grey with the results):
  - WhatsApp's connect time is unknown. `lab/e5/whatsapp_connect.py` (results/whatsapp_connect.jsonl): in 7 of 9 Gate 1 calls the phone's first packet to Meta's relay left 0.7-2.9 s after the tap and the first came back 0.2-0.7 s later; in 2 (p1, p4) none within 40 s. But the iPhone was answered by hand, unlogged, and that traffic starts while the call rings, so no answer moment can be read. Our connect time is reported, no pass or fail.
  - P0 amended: as the lab runs P0, Bob cannot reach the server, so no phone "agrees". calls.py now has Alice place the call anyway (as WhatsApp's caller did) and logs how her app gives up. Rule: Alice's call never connects and her app exits within the 90 s setup deadline plus 30 s.
  - Known before running (cause corrected 2026-11-21: it is E7's 10-steady-seconds start, not the pause setting): Alice's video starts about 12 s after connect even on an open link (e4a: Bob's remote-video 12.1 s after connected), and the freeze measure counts those seconds. It stays counted: it is what the receiver sees.
- Limits written down now: WhatsApp ran on two real phones over the laptop's shaped hotspot and the Wi-Fi; ours runs in containers with the same shaping in netem. Same profiles and same detectors, not the same radios. Three calls per profile can show a large difference, not a small one.
E5 FOLLOW-UP STEP 1b DONE 2026-11-22, does NOT meet its rule (`lab/e5/results/p1_step1b.jsonl`): 60 ms sound, no video stream. Packet rate checked: about 20 sound packets a second each way in every call (against about 47 at 20 ms), so the setting took. P1 direct: voice 416, 378, 375 ms (median 378, under WhatsApp's 696), 17 of 17 clicks each; round trip at most 0.54, 0.54, 4.82 s (rule: under 1 s; one spike). P1-blocked: 986, 694, 7,751 ms (median 986), round trip median 0.92, 0.92, 16.8 s, at most 3.4, 11.4, 28.9 s; 16, 15, 14 of 17; the relay's queue at most 51 packets in the first, against its 1000-packet limit at 20 ms.
E5 FOLLOW-UP STEP 1b PLAN, 2026-11-22, Grey's go ("yes"): the same 6 calls (P1, P1-blocked, 3 each, no video stream) with one change, the sound sent as 60 ms packets (`--opus-ptime 60`, about 17 a second) instead of 20 ms (50). Same rule as step 1. Also checked from each phone's capture: the packet rate really fell to about 17 a second; if it did not, the run is invalid, not a result.
E5 FOLLOW-UP STEP 1 DONE 2026-11-22, the idea does NOT hold by its rule (`lab/e5/results/p1_step1.jsonl`): with no video stream, P1 direct voice medians 727, 813, 744 ms (median 744, against 696), round trip at most 0.96, 1.10, 1.38 s (rule: under 1 s), 17 of 17 clicks each; against 11.6 s and 23 s with video. P1-blocked unchanged: 16.2, 16.8, 16.6 s, round trip up to 35 s, 12-13 of 17; the relay's own 50 kbit/s queue fills to its 1000-packet limit (e5nv1), carrying both phones' sound, each 40-48 kbit/s on the wire. Step 2 is not done, per the plan.
E5 FOLLOW-UP PLAN (P1, the 2G-like link), 2026-11-21, Grey's go ("ok") for step 1.
- Measured already (e5r3 P1, `lab/e5/RESULTS.md`): with no video frames sent, Alice's video stream sends padding at 17-19 kbit/s; her queue fills to its limit and the round trip reaches 23 s; the voice runs 9-23 s late.
- Idea to test: that padding is what fills the link. Step 1 changes nothing in the app: 3 calls on P1 and 3 on P1-blocked with `--no-video` (no video stream at all). If the round trip stays under 1 s and the voice median is at or under WhatsApp's 696 ms, the idea holds; if the queue still fills, it is wrong and step 2 is not done.
- Step 2, only if step 1 holds: stop the padding while video is not sent. The app stops video with replaceTrack(null), which leaves the stream open; the standard way to silence a stream is its encoding's `active: false` (W3C WebRTC 1.0, RTCRtpEncodingParameters), which flutter_webrtc 1.6.2+hotfix.4 on Linux ignores (it changes a copy of the encodings, found 2026-10-18). Fix that in the plugin (patched dependency, reported upstream), then use it. Proof in the calls test first: a stream set inactive sends no bytes, headers included, over 10 s; and it fails on the unpatched plugin.
- Step 3: 3 calls each on P1, P1-blocked, P2, P2-blocked, P3, P3-blocked with the fix, judged by E5's rules. Also required: P2 and P3 no worse than their E5 medians.
- Will still fail after this, said now: P1's frozen video. Video never starts on P1 (E7's steady-link rule), so the screen shows no moving picture for the whole call, which freezedetect counts as frozen (60 s/min against WhatsApp's 14.2). That is E7's question, not this fix's.
E5b PLAN, 2026-11-22, Grey's go ("yes"). Like for like (Grey 2026-11-22: "our hardest against meta's hardest is not completely unreasonable, but ... our hardest against their easiest, is definitely not a fair comparison"). E5 shaped both phones, the server and the relay; Gate 1 shaped only the Android phone (the shaped hotspot, both directions, `lab/baseline/shape.sh`, ifb for the downlink), with the iPhone on home Wi-Fi for P1-P4 and Meta's relay on a fast link. E5's P5 and P0 rows already match Gate 1 (both phones on the hotspot there too) and stand.
- A, Gate 1's arrangement (a field phone on its own weak link, the consultant on a normal one, a cloud server and relay): only Alice's link shaped, both directions, as shape.sh does it; Bob, server and relay unshaped. P1, P2, P3, P4, each direct and relay-forced, 3 calls, 3 minutes, shipped defaults. Judged by E5's rules against WhatsApp's numbers. 24 calls, about 2.5 hours.
- C, the ground server (D11) with a weak uplink: Alice, server and relay on the clinic's local network, Bob outside, so everything Bob sends or receives crosses the uplink: only Bob's link shaped. Same profiles and counts. WhatsApp cannot run a relay on site, so no WhatsApp number: reported, no pass or fail. 24 calls.
- New in calls.py: `--shape-only alice|bob`, shaping that one container both ways (ingress through ifb, as shape.sh). Proved first under a known condition: with `plus500`-style 500 ms one way on Alice only, the voice delay reads about 500 ms more than unshaped, both directions of the call; and Bob's interface shows no netem.
- Shipped defaults on purpose: the two findings from E5's follow-up (the empty video stream's padding, 60 ms sound packets) are tested against A afterwards, one at a time.
- Later, Grey's to decide, not in this plan: WhatsApp's hardest case (both phones on the shaped link) needs a new Gate 1 session on two real phones, to set beside E5's both-shaped numbers.
| E6 | Completion rate | 50 calls on P1 (Gate 4), completion at or above WhatsApp's on P1 | `SUCCESS.md` Gate 4 |
| E7 | Video falls back to audio | on P1 with video on, the call keeps sound and says video is off, rather than freezing | `SUCCESS.md` Gate 5, `DESIGN.md` |
| E7, decided | Video comes back only on a tap | Grey 2026-10-18: once stopped, video stays off until the person taps "try video again"; a tap on a link still weak stops it again after five weak seconds. Why: each automatic try in calls19-20 refilled the link's queue and slowed the voice for minutes (calls19b P1: the link jammed within 9-10 s of each try; calls20d: clicks took 2.7-2.8 s for two minutes after the second try). The call still starts with sound only and sends video by itself once the link has been steady for 10 s. Video the engine holds back below its lowest rate (not stopped by the guard) comes back by itself when the engine's estimate allows: calls40 (2026-11-19), back 16.9 s after the link improved, voice within the rule Grey agreed (D17). | Grey |
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

E5b DONE, 2026-11-22 (lab/e5/RESULTS-E5b.md). A, Gate 1's arrangement: P1 fails voice and frozen (direct 16.4 s voice, relayed 1.2 s; frozen 60 s/min both; WhatsApp 0.70 s, 14.2); P2 fails frozen (4.62 direct, 4.22 relayed; WhatsApp 3.4); P3 passes frozen (4.35, 4.73; WhatsApp 6.0); P4 survives 3/3. C reported only: P1 12.1 s / 2.6 s voice, frozen 60; P2-P3 as A. Next: video padding fix, then 60 ms packets, each against A, each on Grey's go.
