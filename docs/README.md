# Tremulator — planning corpus

Secure clinician-to-clinician messaging (text, audio, video) for field and
remote-consult use. **Phase 0. No code until Gate 0 closes.**

Companions: [OPTIONS.md](OPTIONS.md) (ecosystem evidence and the build/adopt
recommendation) · [THREAT-MODEL.md](THREAT-MODEL.md) · [QUESTIONS.md](QUESTIONS.md)
(Grey's open decisions) · [SUCCESS.md](SUCCESS.md) (gates, numbers, tests).

## What it is

A Dart/Flutter package family in the FHIR-FLI shape: a model-independent
protocol and workflow engine, plus thin adapters. Tremulator owns the clinical
layer. It does not own the cryptographic primitives and does not reimplement a
messaging protocol.

| Layer | Owner | Why |
|---|---|---|
| Primitives (X25519, AES-GCM, Megolm/MLS) | audited Rust, via FFI | Dart has no constant-time guarantees, no key zeroisation, no control of swap |
| Transport + E2EE session state | adopted protocol behind a `TremulatorTransport` interface | protocol reimplementation is where CVEs live |
| Media | WebRTC (P2P DTLS-SRTP for 1:1; SFU + frame cryptor beyond 2) | 1:1 P2P is genuinely end-to-end with no server in the media path |
| Directory, consult workflow, retention, chart write-back, call orchestration | **tremulator** | this is the part no existing app does |

## What it is not

- Not a new cryptographic protocol.
- Not a hosted service. Every deployment operates its own server, TURN relay
  and push credentials, or contracts someone to.
- Not metadata-hiding. Who called whom, when, and for how long is visible to
  whoever runs the server and to the network. Stated, not mitigated.
- Not a replacement for the chart. See Q3.

## Why not just use Signal

Four differentiators. If a deployment needs none of them, the correct answer is
Signal plus a written policy, and Gate 0 says so out loud.

1. **Directory tied to clinical role.** FHIR `Practitioner` / `PractitionerRole`
   / `Endpoint` scoped to a deployment roster, not a phone-number graph.
   This is what gematik's TI-Messenger does with its FHIR VZD directory.
2. **Chart write-back.** The consultant's recommendation lands in the record,
   attributed, timestamped, and it is the record that persists.
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
