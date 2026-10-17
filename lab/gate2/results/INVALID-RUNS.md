# Invalid runs, kept as the record of the instrument defects they found

- **run1-invalid** (2026-10-06 23:26): the client never started in the
  container: `libopenmls_frb.so` not found, then GLIBC 2.38 missing on
  bookworm. And the canary scanner was handed the directory holding its own
  canary list, so it reported 40 hits of its own input. Both fixed in
  `bf62bd3`.
- **run2-invalid** (2026-10-06 23:28): P1 summarised 13 s before Bob
  finished (the wait probed a process name that never matched), so it counted
  14 delivered of a real 20, and the capture and store dump were cut early.
  Fixed in `1052eee`. Its P1 logs are complete and show 20/20.
- **run3-invalid** (2026-10-06 23:31): P1 is valid (20/20, median 26.1 s,
  max 48.7 s at one message a second). From P2 on, P1's server was still
  running (the stop killed by process name and missed), so each later
  profile ran against P1's store; Bob, with wiped keys, could not open a
  welcome built on his old key package, and his client crashed on the
  unknown conversation. Fixed in `d173451`: server killed by recorded pid,
  one port per profile, empty-store assertion at start, client reports
  instead of crashing.
- **calls1-invalid** (2026-10-10 08:49): the call itself is valid (connected
  in 402 ms host to host, Bob decoded 850 frames, 0 in the stats' freeze
  count, ~1,420 audio packets each way; fingerprints 0 hits on the server,
  2 in the positive control). Bob's screen recording is not: it is frozen
  from frame 0 to the end. Two defects. The app built `RTCVideoView` once,
  and that widget picks texture or placeholder when built, so it showed the
  placeholder all call. And the summary read the frozen recording as 0
  freezes, because freezedetect prints no duration for a span still open at
  the end. Fixed in the next commit: the view rebuilds on every renderer
  change; freezes are spans clipped to Bob's connected..call-ended window,
  an open span runs to the end (checked on calls1: one span 0-90 s; on a
  laptop run: still before and after the call only).
- **calls2-invalid** (2026-10-10 09:00): the call and the picture are valid
  (connected 374 ms, 847 frames, the pattern on Bob's screen). Its 2.17 s
  of "frozen" video is not the link: 2.15 s is the start of the call, while
  Alice's screen still showed her own still app window (the pattern went up
  3 s after her app), and 0.02 s is the last frame. Fixed in the next
  commit: the pattern starts first and her window is lowered under it, and
  Alice's screen is recorded too, so a freeze on Bob's alone is the link's.
- **calls3-invalid** (2026-10-10 09:04): Alice's app window covered the
  test pattern all call, so both screens are one still picture (60 s frozen
  per minute on each; the two-screen control caught it). The step meant to
  put her window under the pattern called `xdotool windowlower`, which
  Ubuntu 24.04's xdotool (3.20160805) does not have. Fixed in the next
  commit: the pattern window is raised instead (`windowraise` exists).
- **calls6-invalid** (2026-10-16 19:25): the first run of the step-3
  pieces, profiles none, none-blocked, plus500, P5 at 30 s. Three lab
  defects, no app defect found:
  1. Sound: both recordings are 520-byte headers with no sound, so no voice
     delay. `-copyts` kept the wall-clock stamp but made `-t` count from 0,
     so ffmpeg stopped at once. Reproduced in a scratch container (no
     network). Fixed: no `-copyts`; the stamp is read from the `start:`
     ffmpeg prints for its PulseAudio input.
  2. Shaping: `plus500` stopped the run, "netem on g2c-turn: Operation not
     permitted". The calls image runs as `ubuntu`; NET_ADMIN reaches only
     root. calls1-5 ran unshaped only, so this never showed. Reproduced
     both ways in a scratch container. Fixed: labkit's tc commands run as
     root. P5 never ran.
  3. Picture, `none` only: Alice's app window sat above the test pattern
     all call, so both screens are one grey picture (60 s frozen per minute
     on each; the two-screen control caught it). The raise had run
     (`pattern_raised` true) but too early. Fixed: the raise waits for the
     app window to be visible and repeats until the window stack shows the
     pattern on top; the stack is read again when the call connects.
  Valid in it: `none` connected direct in 537 ms; `none-blocked` (direct
  route blackholed, proved by a refused-then-invalid TCP probe) connected
  through the relay in 570 ms, Bob decoded 775 frames at 960x540, 0.16 s
  frozen (0.32 s per minute); fingerprints 0 hits on the server, 2 in the
  control, in both.
- **Voice delay, calls6 to calls9-before** (found 2026-10-17): the start
  time of each sound recording came from the `start:` ffmpeg prints for
  its PulseAudio input. Measured under a known condition
  (`pulse_stamp_check.py`, one sound recorded twice in one container,
  true difference 0): off by 273-722 ms over 8 trials, and 60-719 ms with
  a 10 ms buffer, different on every recording. So each call's voice
  delay carries its own unknown offset of up to about 0.7 s; the spread
  of clicks inside one call is not affected (one offset per call). Seen
  in calls9-before: Bob "heard" clicks 0.27-0.46 s before Alice sent
  them on cut60 and cut120. Fixed: every 10 ms packet is stamped with its
  arrival and the start is the earliest (arrival - audio before it); the
  same check then reads 0 ms in 8 of 8 trials (24 clicks). Still invalid:
  the voice-delay medians of calls7 and calls8 (and the plus500 check's
  +542 ms, n=2) until re-measured. Valid in calls9-before: every call
  survival and timing fact (cut20, cut60, cut120 on the build before
  reconnection: each call ended "failed" 16 s after the link went).
- **Shaping never cleared between profiles, every run up to calls9**
  (found 2026-10-17): labkit.clear_shaping killed the shaping loops by
  matching their tag in command lines, from a shell whose own command line
  held the tag, so it killed itself (exit 143, reproduced in g2c-turn)
  before removing the shaping. A profile that sets its own shaping replaced
  the old (tc replace), so shaped-after-shaped profiles were unaffected.
  Affected: (1) calls9 from cut20 on: the server and relay kept plus500's
  500 ms each way (read with tc in the running containers); stopped there,
  re-run as calls10; calls9 `none` and `plus500` are valid. (2) calls8
  P4-blocked and P0: P4's 30 s up / 60 s down loop kept running, and
  P4-blocked started a second one over it. (3) run4-run6 P0 (text): P4's
  loop was still running on those containers; not yet checked how much
  of P0 it reached. Fixed: each loop records its pid and clear_shaping
  kills by it, then fails unless no netem and no loop is left;
  `shaping_check.py` (one container, netem + duty loop + cut, cleared,
  watched 40 s) passes.
