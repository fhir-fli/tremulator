# Current design

**This is where the design stands today, not a settled record.** Everything here
was decided in one conversation on 2026-09-20 and 2026-09-21 and is expected to
change. Each entry says what we chose and the reasoning, so that when it changes
we know what we are giving up. Nothing in it is frozen.

D5 is the exception: Grey has settled it more than once and it is not to be
raised again.

## D1. MLS, not Matrix. 2026-09-21

Key agreement is MLS, RFC 9420, through the `openmls` Dart package, which wraps
the Rust OpenMLS implementation and is **MIT**. The Rust crypto is compiled in
through flutter_rust_bridge and all six Flutter platforms are listed, web
included.

Why not Matrix: its Dart client is AGPL-3.0 and would make bumblebee and every
app that links it AGPL. Its group key management, the thing it does best, is
dead weight for one-to-one consults. Its calling code is described as
experimental by FluffyChat, the most-shipped client on it.

**This closes Q1.** Nothing in the stack is AGPL and the repo stays MIT.

Risk carried: the `openmls` Dart wrapper is one maintainer, 9 stars, created
2026-02-09, last pushed 2026-09-20. The Rust library under it is the mature
part. If the wrapper is abandoned we maintain our own, which is the same
generator run either way.

## D2. fhirant is the delivery service. 2026-09-21

Grey, 2026-09-21: *"I think fhirant is fine."* It gains four jobs, none of
which handle plaintext:

1. the roster, which is a Practitioner list it already understands, binding a
   clinician to their signing key;
2. each device's stock of key packages, so someone can be added while offline;
3. a mailbox holding messages for a phone that is off;
4. passing call setup messages.

Only public keys reach it. Every private key stays on the device. Read from
RFC 9420 section 10: a key package is a version and cipher suite, a public init
key, and a leaf node carrying an encryption key and a signature key, all signed
by the device.

Not chosen: atsign's atServers, which would mean running their server for a job
our own server can do. Not chosen: a purpose-built relay, which is one more
thing to run and patch.

## D3. A cloud fhirant is a peer, not a backup. 2026-09-21

Grey's call, and correct: if the ground server is offline or dead, the cloud
copy is the only one a remote consultant can reach.

## D4. The cloud server orders messages. The ground server owns clinical data.

MLS state is ordered. Each change to a conversation is a numbered epoch, and
two servers delivering the same changes in different orders leaves devices
unable to read each other. FHIR resources have no such constraint.

So the ordering authority is the cloud server, on the reasoning that the ground
link is the unreliable one and a consultant should not be blocked by it. **This
is reasoning from the design, not a measurement.** It is a Gate 2 experiment:
run both arrangements against the intermittent network profile and count
messages that fail to send.

Consequence, accepted: a deployment with no internet has no messaging to the
outside, which was already true. Two phones in the same tent with no internet
is a separate requirement, still open.

## D5. Syncing clinical data is not hard here. 2026-09-21

Grey, 2026-09-21, after I had raised it repeatedly: last write wins, patch the
few fields that actually change, keep versions and timestamps, and conflicts
are rare and visible. That is the model. **Settled. Do not relitigate it.**
The exception is D4, which is about key state, not clinical data.

## D6. NoPorts does not help here. 2026-09-21

Read their documentation and repository on 2026-09-21. BSD-3, 283 stars, active.
Neither endpoint opens a listening port; both dial out to a relay that bridges
two TCP sockets, with the setup carried over the atProtocol and the traffic
carrying another AES-256 key.

It removes attack surface. It does not hide an IP address: the relay sees both
ends, with times, durations and volumes. Their "invisible to prying eyes" line
is about ports, not anonymity. The relay is self-hostable, which puts that
metadata in the deployment's hands.

No use for text, which already goes through a server, and none for calls, since
it bridges TCP and real-time media wants UDP. Keep it in mind for reaching a
machine rather than a person: a clinic laptop, a field server, an ultrasound
workstation behind a hospital firewall.

## D7. Multiple enrollers, and the deployment picks one or two signatures. 2026-09-21

Grey, 2026-09-21: *"I think multiple enrollers. Maybe we want to add folks at a
different university or in the capital or something. And I think we should allow
the group to choose. So we should make it possible with one or two people to
approve."*

- Several people hold the enroller role, and they need not be in the same place.
  One enroller asleep or out of signal blocks a consult.
- The enroller signs the new person's key into the roster. Phones trust the
  signature, not the server, so a compromised server cannot invent a consultant.
- Every addition is visible to the whole deployment: who was added, by whom,
  when. Visibility, not an approval step.
- The threshold is the deployment's setting: one signature or two.

Falls out of making the threshold configurable, and has to be built in from the
start: **changing the threshold requires the higher threshold, and so does
removing an enroller.** Otherwise one enroller sets it to one and adds
themselves.

Settled 2026-09-21, same conversation. Thresholds are per category and every one
of them can be set to a single signature, **including access to the protection
cases**. Grey: *"Some groups may not want that much trouble to access records.
So as I said, we should have the ability to only have one signature to reach
protection cases."* A rule that blocks care at 2 a.m. is worse than the risk it
removes, and that is his call to make.

What carries the accountability instead, at no cost to the clinician: whatever
the threshold, both the enrollment and the access to a restricted record are
recorded and visible to the deployment. Nobody is slowed down, and the question
can still be answered afterwards.
