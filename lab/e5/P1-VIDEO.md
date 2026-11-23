# Why P1 shows no video (from E5d's own files, 2026-11-23)

Scripts: `start_signals.py`, `pcap_kinds.py` (Alice's uplink by kind, from
her media capture), `queue_max.py`. Outputs: `results/start_signals.txt`,
`results/e5d_p1_uplink_kinds.txt`.

Two things stop it, in order.

1. The guard refuses video at the start in 4 of 6 P1 calls (all 3 relayed,
   e5d2 direct). In the first 15 s after connect Alice's link queue reaches
   100-211 packets and the round trip 2-5 s; the guard counts that as weak
   and keeps video off for the call. What fills the queue:
   - relayed, 3 of 3: connection checks to Bob's blocked direct address at
     about 20 kbit/s (packets every ~40 ms) for ~16 s, on top of the sound
     (about 15 kbit/s with headers);
   - e5d2 direct: WebRTC's bandwidth probe, header-only packets on the
     video's resend stream (payload type 97, its SSRC is the video's rtx
     SSRC) at 43.5 kbit/s for 4 s, while video was still off. In the two
     direct calls where video started the probe was 17 packets.
2. When the guard does start video (2 of 6), the engine pauses it within
   3 s and never resumes. The estimate leaves about 24 kbit/s above the sound
   (estimate 39.5 kbit/s; sound 15). A paused stream resumes only with its
   minimum plus at least 20 kbit/s free (libwebrtc call/bitrate_allocator.cc,
   kMinToggleBitrateBps = 20000, read 2026-11-23 from
   webrtc.googlesource.com main; m150's copy not checked). The video
   minimum's default value was not found in the source read.

Not checked: whether WhatsApp's video at 2G is a lower rate, a lower frame
rate, or both; whether the flutter_webrtc desktop plugin can change ICE
check pacing (its RTCConfiguration has no such field) or the probe.
