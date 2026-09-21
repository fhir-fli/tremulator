# Gates, numbers and tests

The rule for every gate: the instrument is built and validated before the thing
it measures exists. No gate closes on an opinion.

## Gate 0 — Decide

Exit: every item in [QUESTIONS.md](QUESTIONS.md) answered or deferred with a
date. Licence decided. Threat model signed. Regulatory register written from
sources read, not assumed: 45 CFR 164.312 (done, 2026-09-20), plus the data
protection acts of every deployment country, plus GDPR if a European
organisation is in the chain.

Reading list:
- MLS, RFC 9420. Sections 1 and 10 read 2026-09-21; the rest, including the
  security considerations in section 16, not yet.
- The `openmls` Dart package source and its test suite, and how complete its
  coverage of the Rust API is.
- ICRC Handbook on Data Protection in Humanitarian Action, 2nd edition,
  messaging chapter. Retention sections read 2026-09-21.
- Chandra et al 2023, the Grady secure-messaging implementation, J Med Syst 47(1):56
- Mars, Morris and Scott 2019, "WhatsApp Guidelines — What Guidelines?",
  J Telemed Telecare 25(9):524-529

## Gate 1 — Instrument, before any product code

Five network profiles under Linux `tc netem`, each reproducible to ±10% on a
repeat run:

| Profile | Downlink | RTT | Loss | Pattern |
|---|---|---|---|---|
| P1 rural 2G | 50 kbit/s | 400 ms | 5% | steady |
| P2 congested 3G | 300 kbit/s | 200 ms | 2% | steady |
| P3 satellite | 1 Mbit/s | 700 ms | 1% | steady |
| P4 intermittent | 300 kbit/s | 250 ms | 2% | 30 s up, 60 s down |
| P5 field LAN | 10 Mbit/s | 5 ms | 0% | no internet route |

Exit criteria:
1. A reference application (Signal, Element or WhatsApp, chosen in Gate 0) is
   measured on all five profiles. Those numbers become the targets for Gates
   3 to 5. We do not invent a target.
2. Instrument validated in both directions: a 0 kbit/s profile fails the
   reference app, and P5 succeeds. An instrument that never shows a failure is
   broken.
3. Adversary harness: server database dump plus full packet capture, with an
   automated check that no plaintext clinical string appears in either.
4. Mutation test on the adversary harness: at least five injected defects, all
   caught. Defects to inject include a plaintext build, a skipped device
   verification, a key reused across sessions, a purge that unlinks without
   destroying the key, and an attachment uploaded unencrypted.

## Gate 2 — Spike the chosen stack

Two real handsets, one in the United States and one on an international mobile
network. The stack from DECISIONS.md: MLS through `openmls`, a fhirant mailbox,
WebRTC with its fingerprints carried over MLS. Nothing merged.

Measured per profile: call setup time; fraction of calls that stay
peer-to-peer versus falling back to a relay; one-way audio delay; video freeze
seconds per minute at five bandwidth caps; text delivery rate and median
latency across a 24-hour intermittent replay.

Also measured here, because D4 is open: run the ordering server on the ground
and in the cloud against the intermittent profile, and count messages that fail
to send. That number decides D4.

Exit: numbers against the Gate 1 reference baseline, and either confirmation
that `openmls` does what we need or a written reason it does not.

## Gate 3 — Text

- 100% of messages reach the intended recipient across a 24-hour P4 replay.
- 0 plaintext clinical bytes in the server database dump or the packet capture.
- A substituted device key is detected and surfaced, not silently accepted.
- A revoked device reads nothing sent after revocation.
- Purge: after the retention window, the content is unrecoverable from the
  on-device SQLCipher database and from the server store, verified by
  inspecting both, not by trusting a delete call. The purge destroys the keys
  (D8).
- Delivered and seen receipts reach the sender for every message in the
  24-hour replay, including messages sent while the recipient was offline (D9).

## Gate 4 — Audio

Call completion rate on P1 at or above the reference app's rate on P1, over at
least 50 attempts. Median setup time recorded. Audio must survive when video
cannot.

## Gate 5 — Video

Same on P2 and P3. A written degradation policy, tested: when bandwidth falls
below the floor, the call drops to audio and says so, rather than freezing.

## Gate 6 — Clinical

Scripted consult scenarios run end to end, with oracle checks against the FHIR
record, in the shape bumblebee's 1,000-visit Idai day already uses:

- the consultant's recommendation lands in the record, attributed to the
  consultant, with the time it was given
- the audit trail records who joined a call and when
- the retention policy applied to the channel did not remove anything the
  record needed
- a consult begun offline on P5 and finished after reconnection produces one
  coherent record, not two

## Gate 7 — Review and pilot

Independent protocol and cryptographic review by someone who is not us, paid.
Then a field pilot, measuring the two governing numbers from the README: share
of consults that happen inside tremulator rather than WhatsApp, and call
completion on the worst profile. Also measured: minutes to onboard a new
clinician with no IT support, and how many handsets in the deployment can run
it at all.

## Standing test categories

| Category | What it asserts | Source of truth |
|---|---|---|
| Crypto known-answer | primitives behave | upstream library's own vectors, never ours |
| Protocol conformance | we speak the adopted protocol | the published specification |
| Interoperability | a reference client can talk to us | an existing shipped client |
| Adversary | the server and the wire see no content | the harness above |
| Network | delivery and call quality | the five profiles |
| Recovery | lost phone, new phone, restored history | scripted device lifecycle |
| Failure modes | push never arrives, call drops mid-consult, storage full, battery dies | scripted fault injection |
| Clinical scenario | the record is right | FHIR oracle checks |
