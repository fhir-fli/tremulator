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
