Paste as a comment on https://issues.webrtc.org/issues/489157997

---

We hit this in a calling app and measured it (flutter_webrtc 1.6.2+hotfix.4 on Linux, its bundled libwebrtc).

Setup: audio and video in one MediaStream. The sender stops video with RTCRtpSender.replaceTrack(null); audio keeps flowing. Shaped lossy link, direct and through TURN.

On the receiver, audio inbound-rtp after video stops: jitterBufferTargetDelay stays at 466-1,375 ms while jitterBufferMinimumDelay is 40-100 ms, for the rest of the call.

12 calls, video stopped and restarted every 60 s: audio held more than 100 ms above the minimum in 15 of 23 video-off minutes with one stream, and 0 of 22 with audio and video in separate streams.

This matches the early return in RtpStreamsSynchronizer::UpdateDelay. https://webrtc-review.googlesource.com/c/src/+/460381 looks like it fixes it. Could it be reviewed? Until then we send separate streams and give up lip sync.
