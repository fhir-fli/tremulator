# Tremulator — planning corpus

Secure clinician-to-clinician messaging (text, audio, video) for field and
remote-consult use. **Phase 0. No code until Gate 0 closes.**

Companions: **[DECISIONS.md](DECISIONS.md) (settled, read first)** ·
[OPTIONS.md](OPTIONS.md) (ecosystem evidence) · [THREAT-MODEL.md](THREAT-MODEL.md) ·
[QUESTIONS.md](QUESTIONS.md) (Grey's open decisions) ·
[SUCCESS.md](SUCCESS.md) (gates, numbers, tests).

**The stack, settled 2026-09-21:** MLS (RFC 9420) through the MIT `openmls`
Dart package for keys, fhirant as the delivery service, WebRTC for media, a
cloud fhirant as a peer. See DECISIONS.md.

## What it is

A Dart/Flutter package family in the FHIR-FLI shape: a model-independent
protocol and workflow engine, plus thin adapters. Tremulator owns the clinical
layer. It does not own the cryptographic primitives and does not reimplement a
messaging protocol.

| Layer | Owner | Why |
|---|---|---|
| Keys and encryption | MLS, RFC 9420, through the MIT `openmls` package (Rust underneath) | Dart cannot wipe keys from memory or guarantee constant-time comparisons |
| Delivery, roster, key package store | fhirant, plus a cloud fhirant as a peer | it already runs in the deployment; it never sees plaintext |
| Media | WebRTC through `flutter_webrtc`, MIT, fingerprints carried over MLS | two phones connected directly have no server in the media path |
| Enrollment, receipts, purge, call orchestration | **tremulator** | the part no existing app does for a deployment roster |

## What it is not

- Not a new cryptographic protocol.
- Not a hosted service. Every deployment operates its own server, TURN relay
  and push credentials, or contracts someone to.
- Not metadata-hiding. Who called whom, when, and for how long is visible to
  whoever runs the server and to the network. Stated, not mitigated.
- Not the patient's record. Messages are deleted on a schedule; the notes
  clinicians already write are the record (DECISIONS.md D8).

## Why not just use Signal

Four differentiators. If a deployment needs none of them, the correct answer is
Signal plus a written policy, and Gate 0 says so out loud.

1. **Directory tied to clinical role.** FHIR `Practitioner` / `PractitionerRole`
   / `Endpoint` scoped to a deployment roster, not a phone-number graph.
2. *(Withdrawn 2026-09-21.)* Chart write-back is not a messaging feature;
   clinicians already document in notes (DECISIONS.md D8).
3. **Retention as a verifiable deployment operation.** Purge destroys keys on a
   schedule the deployment sets, and a test proves the content is unrecoverable.
4. **Degraded and offline operation.** Field LAN with no internet; audio that
   survives when video cannot.

## Roadmap

Each gate exits on a number, not an opinion. Full criteria and test lists in
[SUCCESS.md](SUCCESS.md).

| Gate | Name | Exits when |
|---|---|---|
| 0 | Decide | every item in QUESTIONS.md answered or deferred with a date; licence decided; threat model and regulatory matrix written from sources read |
| 1 | Instrument | 5 network profiles reproducible ±10%; a reference app's baseline numbers recorded on all 5; adversary harness catches ≥5 injected defects |
| 2 | Spike | two real handsets, international path, both candidate transports measured against the Gate 1 baseline; transport chosen in writing |
| 3 | Text | E2EE text + attachments, device verification, revocation, purge verified irrecoverable on device and server |
| 4 | Audio | call completion on the worst profile at or above the Gate 1 reference number |
| 5 | Video | same, plus a degradation policy that falls to audio rather than failing |
| 6 | Clinical | scripted consults pass oracle checks against the FHIR record |
| 7 | Review and pilot | independent protocol review; field pilot measured |

## Governing numbers

Two, decided in Gate 0 and measured in Gate 7:

- **Share of consults that happen inside tremulator** rather than WhatsApp, in
  a real deployment. Everything else is irrelevant if this is low.
- **Call completion rate on the worst network profile**, against the reference
  app's rate on the same profile.
