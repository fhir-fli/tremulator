# Padding while video is off (2026-11-25)

What: Alice sends video packets with no media while her video encoding is
inactive. Counts per call, E5d-E5f: `results/e5def_idle_video_packets.txt`
(17 in most calls, up to 1,755). On the wire it is RTP payload type 97, the
video's retransmission stream (`results/e5f1_p1blocked_uplink_kinds.txt`):
in e5f1 P1 relayed, 24-27 kbit/s from 4 s to 96 s after connect, beside
16-18 kbit/s of sound, on a 50 kbit/s, 5% loss link. Video never started in
that call.

Not the video stream's own padding. libwebrtc branch-heads/7871 (m150, the
prebuilt flutter_webrtc 1.6.3 uses: libwebrtc_version.ini
`libwebrtc.m150.7871.07`), video/video_send_stream_impl.cc:
CalculateMaxPadBitrateBps counts active streams only, and pad_up_bitrate_bps
is 0 (`disable_padding_`) until the encoder has produced a frame.

Likely source, read not yet tested: the loss-based estimator.
modules/congestion_controller/goog_cc/loss_based_bwe_v2.cc (m150) lines
340-351: when the loss-limited estimate is rising and below the delay-based
one, state becomes kIncreaseUsingPadding if PaddingDuration > 0 (default
2 s, line 474; trial key `WebRTC-Bwe-LossBasedBweV2`, line 520; enabled by
default, line 408). goog_cc_network_control.cc lines 670-674: in that state
the pacer's padding rate is max(stream padding, loss-based target), capped
by the pushback target. So on a lossy link the pacer pads up to the
estimate, video or not. Every lab profile but P5 has loss (labkit.py:
P1 5%, P2 2%, P3 1%, P4 2%).

Test: `WebRTC-Bwe-LossBasedBweV2/PaddingDuration:0ms/` turns the state into
kIncreasing (no padding; lines 349-351, 1214). flutter_webrtc 1.6.3 passes
only two fixed field trials (common/cpp/src/flutter_webrtc_base.cc,
EnsureWebRTCInitialized), so applying it needs a plugin change.
