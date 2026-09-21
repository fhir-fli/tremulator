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

## D12. One app, one wake-up relay run by FHIR-FLI, and nothing else. 2026-09-21

Grey, 2026-09-21: one published app that each group points at its own servers,
not an app per group. And the relay is its own program: *"where this is all it
does, the only thing it ever does."*

Why a relay exists at all, from sources read 2026-09-21:

- **Apple, "Establishing a token-based connection to APNs"**: pushes are signed
  with a key from the publisher's developer account, tied to its team ID and
  the app. Only the publisher can wake the app on an iPhone. The key is
  team-scoped, so handing it to groups would also let them push to every other
  app in FHIR-FLI's account.
- **Matrix push gateway specification v1.17**: the published design for one app
  over many servers. Push is *"managed by a distinct entity called the Push
  Gateway,"* drawn as run by the app developer, between each homeserver and
  Apple or Google.
- **FHIR R5 Subscription, payload types**: *"systems SHOULD use the minimum level
  of detail consistent with the use case."* Its `empty` type carries nothing,
  and details are fetched separately.
- **Senator Wyden's letter, December 2023**: governments have requested push
  records from Apple and Google. Apple now requires a judge's order. On an
  iPhone, Apple sees every wake-up whatever we build.
- Epic's own design could not be found publicly. Epic publishes Haiku, so by
  Apple's rule it must run the equivalent. That is a deduction.
- No HHS guidance on push notifications was found. OWASP's mobile standard says
  keep sensitive data out of notifications.

The relay:

- Its own program, not part of fhirant. It holds the Apple key and nothing else.
- Takes "wake this device" from a group's server and passes it to Apple. No
  message content, no names, no patient.
- Stores nothing and logs nothing.
- Only for iPhones over the internet. Android rings through UnifiedPush, which a
  group can host itself (Dart package `unifiedpush` 6.2.0). On the local network,
  iPhones ring through Apple's Local Push Connectivity and never touch it.
- If it is down, iPhones stop ringing over the internet; messages and calls
  still arrive when the app is next opened.
- It is **the one exception to D11**: FHIR-FLI runs this and nothing else.
- A group that will not depend on FHIR-FLI can publish its own build of the MIT
  app under its own Apple account and run its own relay.
- Not Firebase: Grey does not want wake-ups passing through Google.

## D13. Wake-ups go to an address each device registers. 2026-09-21

The architecture choice that avoids regret: the group's server has one wake-up
behaviour for every device. At enrollment each device registers an address;
when that device must be woken, the server sends an empty wake-up to it. What
sits at the address is the device's business. This is the UnifiedPush model,
an endpoint the server posts to, so it follows a published design.

Methods behind the address, and which is the default:

| Device, network | Method | Default |
|---|---|---|
| iPhone, internet | FHIR-FLI's wake-up relay (D12) | yes |
| iPhone, local Wi-Fi | Apple Local Push Connectivity | yes |
| Android, anywhere | the app's own kept-open connection to the group's server | yes |
| Android, anywhere | UnifiedPush through a group-hosted ntfy | option |
| Android, anywhere | Google's push, if a group ever wants it | not built by us |

Why the kept-open connection is the Android default: no extra app for users,
no Google, and the same mechanism on the local network as over the internet.
Cost: Android shows a permanent notification while it runs, and battery use is
**unmeasured**. Gate 2 measures it; if it is poor, UnifiedPush becomes the
default with no change to the server.

Why not Google by default: Grey does not want wake-ups passing through Google.
Standard Android push runs through Google Play services. UnifiedPush's own FAQ
confirms that avoiding it means users install a separate push app.

## D14. The relay is written in Go. 2026-09-21

Its one job is signing requests to Apple with the key (ES256 JSON web tokens).
In Dart the standard package, `dart_jsonwebtoken` 3.4.1, signs through
pointycastle in pure Dart, which step 1 of DESIGN.md rules out. Go's standard
library signs in well-reviewed code, and Go is built for small network
services. Candidate library: `sideshow/apns2`, MIT, 3,189 stars, last pushed
2025-07-22. Grey has written some Go.

The exception to "everything we write is Dart" is this one program.

## D15. Defaults checked against all 195 countries. 2026-09-21

Grey, 2026-09-21: HIPAA plays no role, since patients are not treated in the
United States. Rather than wait for a first deployment, check every country and
set defaults by where most lean. Full table and method:
[research/countries/](../research/countries/README.md).

What the defaults are, and the count behind each:

- **Ground server required, cloud optional**, unchanged. At least 10 of the 146
  countries DLA Piper covers require data to stay in the country (6 in general,
  4 for health data: Kenya, Slovenia, the UAE, Zambia). The ground server
  satisfies all of them; a group there keeps its cloud peer in-country or runs
  without one. The count is a floor: DLA's summary missed Kenya's health rule,
  found only by reading Kenya's regulations directly.
- **Clinical content is sensitive everywhere.** Health data is a sensitive
  category in 123 of 146.
- **Encryption is always on and cannot be switched off.** 13 countries have
  widespread encryption restrictions and 23 have licensing or registration
  rules; they are listed for checking before a deployment. For 106 countries
  the encryption map has no information.
- **Sending clinical content abroad is the use case**, and it is a regulated
  transfer in 131 of 146, allowed on conditions in nearly all. The legal basis
  is the deploying group's to establish; nothing in software turns it off.

Not covered by DLA at all: 49 countries, including Afghanistan, Iraq, Malawi,
Somalia, South Sudan, Sudan, Syria and Yemen. Before deploying anywhere, the
group reads that country's actual law.
