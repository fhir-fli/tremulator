# Build, adopt, or don't build

> **Superseded recommendation.** This file is the evidence gathered on
> 2026-09-20. Its recommendation below, Matrix for the channel, was replaced on
> 2026-09-21 by MLS through the MIT `openmls` package with fhirant as the
> delivery service. See [DECISIONS.md](DECISIONS.md) D1 and D2 for the current
> design and why. The package facts and measurements remain accurate for the
> date they were read.

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

## Recommendation (superseded 2026-09-21, see DECISIONS.md D1)

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

## What replacing the AGPL code would actually cost

Measured 2026-09-20 from the published package archives, not estimated.

| Piece | Hand-written | Machine-generated |
|---|---|---|
| `dart-vodozemac`, the AGPL crypto binding | 682 Dart + 1,167 Rust lines | 10,949 Dart + 7,281 Rust lines |
| Matrix client encryption logic (`lib/encryption`, 17 files) | 7,087 lines | — |
| Matrix HTTP API layer | — | 14,261 lines, generated from the published spec |
| Whole `matrix` package | — | 55,782 lines across 184 files |

Replacing the crypto binding is small, roughly 1,850 hand-written lines plus
generator runs. Replacing the encryption logic is not: 7,087 lines covering Olm
and Megolm sessions, key backup, secret storage, cross-signing and device
verification, every line security-relevant, needing its own tests and an
outside review.

## Correction on atsign, 2026-09-20

`at_chops` 3.7.0 is **not** pure Dart. Pull request 2039, merged 2026-07-09,
added an OpenSSL-backed AES-256-GCM implementation through `dart:ffi`, tested
against NIST vectors, and the post-quantum pieces X-Wing and ML-DSA-65 resolve
through FFI as well. The pure-Dart algorithms remain as the fallback when
libcrypto is unavailable. Which operations still have no native path is
unchecked; RSA and the older algorithms were not examined.

No published third-party cryptographic audit was found. Searched: one web
search, and the GitHub organisation three ways. Their own issue 2146 closes
gaps found by an internal audit, and 1889 tracks post-quantum work. Not finding
a report is not proof there is none. **Grey knows the company and is asking
them directly.**

## What Matrix stores, which Q3 depends on

From the Matrix specification, not measured here. A room is a log held on the
server and replicated to every server with a user in it. Message content is
encrypted, so the server holds ciphertext it cannot read, and holds it until
something deletes it. Calls are different: Matrix carries only the setup
messages, and the audio and video travel over WebRTC without touching it.

So a 72-hour purge is a thing we build and prove, not a thing we get. Federating
with an outside server means that server holds a copy too. Neither claim has
been tested against a running homeserver yet.
