# tremulator_calls

Voice and video calls between phones in a tremulator conversation.

The caller's connection details (the "offer") and the callee's reply (the
"answer") travel as encrypted `call` messages through the mailbox, so the
server never sees them. Each carries the fingerprint of the certificate its
phone will present; WebRTC refuses a connection whose certificate does not
match (RFC 8122 section 6.2). Because the details travel inside the
encrypted chat, a dishonest server cannot swap them.

The details are sent whole, once each, after the phone has found its own
addresses: a mailbox message costs at least one server round trip, so one
offer and one answer beat a stream of address messages.

The media goes phone to phone, or through a TURN relay passed in
`iceServers`.

When a connected call loses its link, it is kept, not ended. The caller
restarts the connection (W3C WebRTC `restartIce()`, then a new offer) and
sends the offer through the mailbox again, retrying until the link is back
or `reconnectGrace` (90 s) runs out; then both phones end the call as
`lost`. Offers and answers carry a number, so an answer to a replaced offer
is ignored. Every description after the first must carry the same
certificate fingerprints as the first, or the call ends as
`fingerprint-changed`.

## Tests

`flutter test` runs the setup-format tests. The call tests need the native
WebRTC plugin, so they run inside the Linux app in `example/`, on a private
virtual screen:

    bash ../../lab/tool/xvfb.sh            # starts Xvfb on :99
    cd example
    DISPLAY=:99 flutter test integration_test/calls_test.dart -d linux

flutter_webrtc is pinned to 1.6.2+hotfix.4: with 1.6.2 the Linux app
segfaulted at start (null audio device in `FlutterMediaStream`), 3 of 3
starts, 2026-10-10.
