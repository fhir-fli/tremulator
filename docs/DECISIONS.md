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

## D8. Messages are throwaway. 2026-09-21

Grey, 2026-09-21: *"I think we can throw it away."* The channel is not part of
the patient's record. Messages are deleted on a schedule the deployment sets.

What the guidance says, and it all says the same thing: the message is
transient, the clinical decision goes into the record, then the message is
deleted.

- **ICRC, Handbook on Data Protection in Humanitarian Action, 2nd edition
  (2020), chapter on mobile messaging apps.** Read verbatim 2026-09-21 from the
  PDF. Section 11.4: *"Humanitarian Organizations should also consider having a
  retention policy concerning the exchanges of information or "chats"
  themselves and delete the chat history at regular intervals to ensure data
  minimization."* Section 11.6: *"it is recommended that Humanitarian
  Organizations also consider having clear policies on deleting chats at
  regular intervals, once the necessary data have been extracted."* Section
  11.2.4.2: privacy *"is better served when the contents of messages are
  delivered to a user's device and deleted from the app company's servers after
  they are read."* Caveat: the chapter is about organisations messaging the
  people they serve, not clinicians messaging each other.
- **NHS England, guidance on mobile and instant messaging in health and care
  settings (2018).** Not read verbatim: the site returned no content to an
  automated request on 2026-09-21. Two news reports from 2018 and the search
  summary agree that it says messaging does not replace the record, clinical
  decisions are transferred to the record as soon as possible, and the original
  messages are deleted. It also asks for the ability to wipe a lost device
  remotely.
- **Grady Health System** (Chandra et al, J Med Syst 2023;47(1):56), via the
  OpenEvidence summary Grey pasted, not read directly: not part of the legal
  record, purged every 72 hours, and not to be used for critical information,
  urgent results or peer-review content.
- **Mars, Morris and Scott**, J Telemed Telecare 2019;25(9):524-529, via the same
  summary: no mandatory national guideline for clinical instant messaging
  exists, only advisories.

What it means for the build: nothing extra. "Transfer the decision to the
record" means document the way clinicians already do. Grey, 2026-09-21: the chat
is the discussion; the consultant writes the official recommendation as a note
anyway, and the field team writes notes at least daily. There is no extraction
feature to build. An earlier draft of this entry said there was; that was wrong.

The purge itself stays simple, since each device holds its own history and the
server keeps nothing once a message is collected.

This also resolves the HIPAA emergency-access conflict in THREAT-MODEL.md: the
record, not the channel, is the source of clinical information.

## D9. The sender sees that a message was delivered and seen. 2026-09-21

Grey, 2026-09-21: *"yes, I want a confirmation something was seen."*

From the OpenEvidence summary Grey pasted, not read directly: the American
Academy of Pediatrics (Webber et al, Pediatrics 2019;144(1):e20191359) cautions
that electronic communication should not drive care decisions without
closed-loop confirmation of receipt.

Two states per message, shown to the sender: delivered to the recipient's phone,
and seen by the recipient. The receipts travel through the same encrypted
channel as the messages.

## D8, addendum: the purge destroys keys. 2026-09-21

Same summary: the American Psychiatric Association's telepsychiatry resource
document (Recupero and Fisher, 2014) warns that messaging systems keep copies
users believe are deleted, and that forensic recovery is often possible. So a
purge destroys the encryption keys for the purged messages, which makes any
leftover copy unreadable, rather than only deleting records. Gate 3 already
tests it by inspecting the phone's storage and the server afterwards.

Also from that summary, and deliberately **not** built into the software: the
Joint Commission's position against orders by text, and restricting chat to
non-critical coordination. Both are deployment policy, each group's to write.

## D10. Every platform Flutter builds for; installed app, not web. 2026-09-21

Grey, 2026-09-21: requiring consultants to install the app is reasonable, and
all FHIR-FLI software targets every platform, phone first, with a laptop usable
whenever one is to hand. Web is questionable.

- Android, iOS, Windows, macOS and Linux. `openmls` lists all five, plus web.
- Store distribution is required on phones: iPhones effectively install only
  through the App Store, and ringing a closed app needs Apple's and Google's
  push services.
- Web is not planned. A browser is a weaker place to hold private keys and a
  closed tab cannot ring.
- Known snag, unmeasured: some hospitals manage staff personal phones with a
  work profile that blocks unapproved apps. A consultant behind one could not
  install. A desktop install on their own laptop is the fallback.

## D11. Each group runs its own, and it must run entirely locally. 2026-09-21

Grey, 2026-09-21: *"no, fhir-fli should not run it. each group should run their
own. IMPORTANT, I want this to be able to run completely locally. So cloud is
nice, and will probably be generally used, but I don't want it to be required."*

- The ground fhirant is the only required server. The cloud fhirant is optional.
- **D4 changes accordingly:** the ground server orders messages by default. A
  deployment that runs a cloud peer may choose to have it order conversations
  that include outside consultants. Which, is measured in Gate 2.
- Ringing a closed app with **no internet**, looked up 2026-09-21:
  - iOS: Apple's Local Push Connectivity (iOS 14+, `NEAppPushProvider`) lets an
    app hold a connection to its own server on named Wi-Fi networks and receive
    pushes, VoIP calls included, without Apple's push service. Built for
    hospitals, ships and campuses. It needs a restricted entitlement requested
    from Apple. A Flutter package, `local_push_connectivity`, exists; not
    evaluated.
  - Android: a foreground service holding a connection to the ground server.
    No Google service involved.
- Ringing a closed app **over the internet** is unresolved. Apple's and Google's
  push services only accept messages signed with keys issued to whoever
  published the app. See QUESTIONS.md.
