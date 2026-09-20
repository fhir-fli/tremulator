# Build, adopt, or don't build

All package facts below were read from pub.dev and GitHub on **2026-09-20**.
Nothing here is from memory.

## What exists in Dart today

| Package / repo | Latest | Published | Licence | Note |
|---|---|---|---|---|
| `matrix` (famedly/matrix-dart-sdk) | 12.0.1 | 2026-09-02 | **AGPL-3.0** | full Matrix client, E2EE, `lib/src/voip` with `call_session.dart`, `group_call_session.dart`, backends `mesh` and `livekit` |
| `vodozemac` (famedly/dart-vodozemac) | 0.8.0 | 2026-08-31 | **AGPL-3.0** | Dart bindings via flutter_rust_bridge 2.13.0 |
| matrix-org/vodozemac (the Rust library) | — | — | Apache-2.0 | the audited crypto itself is permissive; only the Dart binding is AGPL |
| `flutter_webrtc` | 1.6.2+hotfix.3 | 2026-09-15 | MIT | |
| `dart_webrtc` | 1.8.x | — | — | has `frame_cryptor_impl.dart` and `e2ee.worker`, so frame-level media encryption exists in this stack |
| `livekit_client` | 2.13.0 | 2026-09-15 | Apache-2.0 | production SFU client, pins `flutter_webrtc 1.6.2+hotfix.3` |
| `flutter_callkit_incoming` | 3.1.5 | 2026-08-11 | — | CallKit / ConnectionService native ringing |
| `at_client` (atsign) | 3.14.0 | 2026-07-17 | BSD-3-Clause | permissive, Dart-native, no media layer |
| openmls (Rust, MLS RFC 9420) | — | pushed 2026-09-17 | MIT | |
| awslabs/mls-rs (MLS RFC 9420) | — | pushed 2026-09-17 | Apache-2.0 | |
| signalapp/libsignal | — | pushed 2026-09-18 | **AGPL-3.0** | Dart bindings: UNKNOWN, not searched |

## The licence fact that decides the shape

The Matrix Dart SDK and the Dart vodozemac bindings are both **AGPL-3.0**.
Anything that links them is AGPL. That reaches bumblebee (currently MIT) and
blocks publishing a permissive package on pub.dev that depends on them.

Precedent that it can still ship: **FluffyChat** is AGPL-3.0-only, written in
Flutter on this same SDK, and is on the Apple App Store and Google Play.

Two escapes if AGPL is unacceptable, both real work:
- write our own flutter_rust_bridge bindings to matrix-org/vodozemac
  (Apache-2.0) and implement Matrix client-side E2EE against the published spec;
- ask Famedly about commercial licensing. Whether they offer it: UNKNOWN.

## The maturity fact that decides the media layer

FluffyChat, the most-shipped client on the Matrix Dart SDK, describes its audio
and video calls as **experimental** (v2.8.0, 2026-07-20). So the Dart SDK's
calling code is not production-proven, even though the text and E2EE are.

Consequence: do not rest audio and video on `matrix`'s VoIP module. Use WebRTC
directly.

## Recommendation

Three layers, decided separately.

1. **Secure channel, identity, devices, text, async attachments: adopt Matrix.**
   It is the only option where a national healthcare body has already published
   a profile for exactly this use case (gematik TI-Messenger, Matrix v1.17,
   with a central FHIR directory). Following it is cheaper than inventing and
   gives a citation. Gated on the AGPL decision (Q1).
2. **Media: WebRTC directly.** 1:1 uses peer-to-peer DTLS-SRTP with no server
   in the media path, and the DTLS fingerprints are verified over the already
   authenticated Matrix channel, which closes the malicious-signalling-server
   hole. More than two parties, or a P2P failure, falls back to a LiveKit SFU
   with frame-cryptor encryption and keys distributed over the same channel.
   This is what `matrix-dart-sdk`'s `livekit_backend.dart` already does.
3. **Tremulator owns the clinical layer only**, and talks to layer 1 through a
   `TremulatorTransport` interface. That keeps the AGPL inside one adapter
   package and leaves the transport swappable.

## What I am not recommending

- **Writing our own messaging protocol.** The Dart parts (state machines,
  serialisation) are safe. The rest is multi-device fan-out, key rotation,
  revocation, out-of-order delivery, session recovery and verification UX.
  That is months, and it needs a paid external review to be worth anything.
- **atPlatform as the transport.** Permissive licence and Dart-native are real
  advantages, and the store-and-forward data model fits asynchronous case
  referral well. But there is no media layer, no published healthcare profile,
  and Flutter web is unsupported. Revisit at Gate 2 as an async-referral spike
  only, if Gate 0 says web clients are not required.
- **Signal as a library.** libsignal is AGPL too, so it carries the same
  licence cost as Matrix without the healthcare profile or the directory.

## The honest alternative

If Gate 0 finds the deployment does not need the directory, the chart
write-back, the deployment-controlled purge, or offline operation, then the
literature's answer is to use an existing app and spend the effort on written
policy. The UK Information Commissioner's Office reprimand of NHS Lanarkshire
turned on the absence of policy, guidance and risk assessment, not on the
choice of app. Gate 0 has to ask the Miami group which of the four they need
before any of this gets built.
