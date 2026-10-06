# Gate 2 plan: the first working version

Written 2026-10-06. This is the first version of the real app, kept (D16).
Every term of art gets a plain sentence the first time it appears.

## What we are building

One Flutter app and three Dart packages, all in this repo:

| Folder | What it does | Touches |
|---|---|---|
| `packages/tremulator_keys` | Holds each phone's keys and does all encryption and decryption. **The only folder that imports `openmls`.** If that library has to go, this folder is rewritten and nothing else changes. | `openmls` 3.2.1 (MIT) |
| `packages/tremulator_mailbox` | Talks to the group's fhirant server: registers the phone, posts and collects encrypted messages, holds the kept-open connection that tells the phone something arrived. | `fhir_r4`, `fhir_r4_at_rest` |
| `packages/tremulator_calls` | Sets up a voice or video call between two phones. | `flutter_webrtc` 1.6.2 (MIT) |
| `app/` | The phone app. In Gate 2: sign in to a server, pick a colleague, send text, start a call. No enrollment, no purge, no backups, no polish. | the three above |

### Keys (`tremulator_keys`)

`openmls` is a Dart wrapper around OpenMLS, a Rust library that implements
MLS. MLS (RFC 9420) is the published standard for agreeing encryption keys
among the members of a conversation, so that a server carrying the messages
cannot read them. Read from the package's README (pub.dev, version 3.2.1,
published 2026-09-29; repository djx-y-z/openmls_dart, 9 stars, one human
contributor, last push 2026-10-05):

- all key state lives in a Rust-owned SQLCipher database opened with a 32-byte
  key the app keeps in the phone's secure storage;
- a phone makes "key packages" (`createKeyPackageWithOptions`): a signed public
  bundle another phone uses to add it to a conversation without it being online;
- a conversation is created with `createGroup`, a colleague is added with
  `addMembers`, which returns a commit (the change) and a welcome (what the
  new member needs to join, `joinGroupFromWelcome`);
- text is encrypted with `createMessage` and decrypted with `processMessage`.

We use only the three standard cipher suites and pass an explicit list, because
the library otherwise advertises ten experimental post-quantum suites
(README, "What your peers see").

Ordering rule, from RFC 9750 (MLS architecture) section 5.2: the group must
agree on a single commit that ends each epoch. So the server that carries a
conversation keeps its changes in one order, and a phone that sends a change
for an epoch already closed has it rejected by the library and starts again
from the newer state. That is the whole of what "ordering" means in D4.

### Mailbox (`tremulator_mailbox`)

Everything on the server is an ordinary FHIR resource, so fhirant needs no new
code paths, and its existing login, scopes, audit and search apply:

- each phone is a `Device`; its public signing key rides on the Device;
- every encrypted blob is a `Communication` with `sender` and `recipient`
  pointing at Devices (both allowed by the R4B definition, read from
  `StructureDefinition-Communication.json`), `payload.contentAttachment` of
  type `message/mls` (the media type RFC 9420 section 17.10 registers) holding
  the bytes, and a `category` saying what it is: key package, welcome, commit,
  message, call setup;
- a phone collects with `Communication?recipient=Device/<me>&status=in-progress
  &_sort=_lastUpdated` and deletes each one after it is safely stored, so the
  server keeps nothing once collected (D8);
- key packages are Communications with a sender and no recipient; the phone
  adding a colleague takes one and deletes it, so each is used once;
- the kept-open connection (D13, Android default) is fhirant's existing
  Subscription websocket: the phone creates a `Subscription` on
  `Communication?recipient=Device/<me>` and gets `ping` when anything matching
  is written (fhirant `websocket_subscriptions.dart`, R4 subscription.html).

Who modelled it this way before: HL7 Austria's messaging guide carries
directed messages as a Communication with a base64 attachment
(`at-messaging-communication-attachment`). Nobody has put MLS on FHIR that I
could find: searched the web for FHIR with "Messaging Layer Security" (0
relevant results) and for FHIR Communication encrypted delivery guides (the
Austrian and Ontario eReferral guides, neither encrypted end to end).

### Calls (`tremulator_calls`)

WebRTC is the standard the browser and phone call stacks use. The two phones
exchange a description of how to connect ("offer" and "answer"). We send that
description as an ordinary encrypted message through the mailbox, so the
server never sees it. The description carries the fingerprint of the
certificate each phone will present when the media connection starts, and
WebRTC itself refuses a connection whose certificate does not match (RFC 8122
section 6.2: "MUST terminate the media connection with a bad_certificate
error"). That is what "fingerprints carried over MLS" meant.

When the phones cannot reach each other directly, a relay server (coturn, in
the lab on the laptop) sits between them and sees only encrypted media.

## What gets measured, against the WhatsApp numbers in GATE1.md

Per network profile P1–P5, same phone and hotspot setup as Gate 1:

| Measure | Target |
|---|---|
| texts delivered, and median time | WhatsApp: 10/10 everywhere with internet, P1 median 5.3 s |
| call connect time | from the capture, as in Gate 1 |
| calls that stay phone-to-phone vs through the relay | count per profile |
| one-way voice delay | clap test, 10 s silence each side around each clap |
| frozen video seconds per minute | ffmpeg freezedetect, Android side |
| texts over a 24-hour replay of the dropping network (P4) | delivery rate and median time |
| battery over 24 hours with the kept-open connection, idle and in use, vs app closed | D13 |
| messages that fail to send when the ordering server is on the ground vs behind the dropping link | decides D4 |

The "cloud" server for the D4 test is a second fhirant on the far side of the
shaped link in the Docker lab. No money.

## Order of work, each step with its proof

1. **Keys package, laptop only.** Tests: two parties make a conversation,
   exchange ten messages, add a third, remove one, and the removed one reads
   nothing after; a commit sent for a closed epoch is rejected and recovered.
2. **Mailbox package against a local fhirant.** Two command-line clients in the
   Docker lab exchange text across P1–P5. Proof: the delivery numbers, plus the
   Gate 1 canary scan over the fhirant database dump and the packet capture
   showing no readable text. This gives text numbers before any phone.
3. **App on the OnePlus and a second Android** (Grey's partner's phone if it is
   Android; otherwise the Linux desktop build as the second client, D10). Text
   on the shaped hotspot, as in Gate 1.
4. **Calls** with coturn in the lab. Connect time, direct vs relay, voice
   delay, video freeze per profile.
5. **24-hour runs**: P4 text replay, and battery on the OnePlus.
6. **D4 experiment.**
7. **iPhone**, when a TestFlight build exists. iPhone-side freeze and the
   "ring a closed app" check.

Exit, from SUCCESS.md: the numbers above beside the WhatsApp table, and either
"openmls does what we need" or a written reason it does not.

## Unknown until tried

- whether fhirant lets a phone signed in as a clinician create a Subscription
  and bind its websocket, or needs a scope change (a work item, not a blocker);
- whether Grey's partner's phone is Android;
- how a Device carries the public key: an identifier or an extension; decided
  at step 2 from the R4B Device definition.

Every step writes its results to `lab/gate2/results/` on every iteration.
Network lab runs wait for Grey's go each time (GATE1.md).

## Step 1 result, 2026-10-06: keys package built, 9 tests green

`packages/tremulator_keys`, pure Dart, `openmls` 3.2.1. `dart test` downloads
the prebuilt native library on first run (Linux x64 worked first time) and
passes 9 of 9: ten messages each way; a third phone added mid-conversation
reads only what follows; a removed phone reads nothing after and cannot send;
a stranger reads nothing; a key package is single use; state survives close
and reopen with the same key and the wrong key opens nothing; blobs can be
routed by conversation id, epoch and kind without decrypting.

**Finding that changed the design.** The wrapper applies every change to the
phone's own state before returning (`rust/src/api/engine.rs`: `add_members`,
`remove_members`, `self_update`, `flexible_commit` each call
`merge_pending_commit`). So a phone cannot hold a change until the server
accepts it. When two phones change the same epoch, the server keeps the first
and the other phone is out of step. Recovery is the RFC's own: the phone
destroys its stale state and rejoins by external commit from the snapshot
(GroupInfo plus key tree) the winner publishes beside every commit (RFC 9420
section 12.4.3.2). Tested: both phones rotate keys at once, the loser's commit
is refused, it rejoins, the old leaf is gone, messages flow both ways. Cost:
every commit also carries a snapshot to the server. Possible upstream ask,
not filed: a "do not merge yet" option on the wrapper's commit calls.

A welcome cannot be classified from its header (the library parses protocol
messages only), so the mailbox labels welcomes by Communication category.
The wrong-key test prints one `sqlcipher ... hmac check failed` line on
stderr; that is the library refusing the key, as intended.

## Step 2, first half, 2026-10-06: mailbox package built, 6 tests green

`packages/tremulator_mailbox`, pure Dart over `fhir_r4` + `fhir_r4_at_rest`
+ `http` + `web_socket_channel`. Its tests start a real fhirant in the same
process (path dependency on `fhirant_server`, in-memory database, free port)
and pass 6 of 6: a phone registers once and is found by name with its key;
key packages are taken one at a time until the stock is empty; a message is
collected once and the server then holds nothing; **the server keeps the
first commit for an epoch and refuses the second**; the wake-up websocket
pings when something is addressed to the phone; with authentication on, a
signed-in phone works and a stranger is refused.

How ordering works on the server, as built: a commit is one Communication
addressed to every member, with `identifier` = commit system | `<conversation
hex>:<epoch it produces>`, sent with `If-None-Exist` on that identifier. The
first phone's create answers 201; a second phone's answers 200 with the first
one's resource, and the package reports "rejected". The test also posts the
same identifier without the header and gets 201, so the header is what
refuses. A phone catches up by asking for the commit after its own epoch
(`commitAfter`) until none exists; the last one carries the GroupInfo and key
tree it would rejoin from. Commits are not deleted by recipients (the purge
sweep's job); messages and welcomes are, after collection (D8).

What fhirant needed changing: nothing. Open: the websocket route in secure
mode takes no token yet (tests ran it with authentication off); and fhirant
prints its log to stdout.

## Step 2, second half, 2026-10-06: the client, 3 end-to-end tests green

`packages/tremulator_client` joins the two packages: `Client.start` registers
and publishes five key packages; `open(peer)` takes a key package, adds the
peer, sends the welcome and offers the commit; `send`; `collect` (welcomes
join, messages decrypt, each acknowledged, then every conversation walks
forward through newer commits); `listen` collects on each wake-up ping;
`refreshKeys`. `bin/tremulator_client.dart` is the lab's phone with no
screen: it logs one JSON line per event, flushed, with the sender's clock in
each message so the receiver's line carries the one-way time.

Tests, against a real fhirant in the same process: two phones exchange ten
messages each way and the server then holds nothing collectable; a wake-up
ping makes the listener collect on its own; **a phone whose commit lost the
race rejoins and talks again**, end to end through the server.

Two more findings while building it:
- A phone can be out of step without knowing: it applied its own commit
  locally and never learned the server refused it (a crash between the two).
  So every commit now also publishes the epoch's **confirmation tag** (RFC
  9420 section 6.1: "confirms that the members of the group have arrived at
  the same state"), and on every collect a phone compares its own tag with
  the server's commit for its epoch. A mismatch means rejoin.
- The rejoin walk first read the commit's header epoch as "the epoch it
  produces" and looped on the same commit until fhirant's rate limit (600
  requests a minute) answered 429. Fixed by counting epochs; the 429 was the
  instrument catching it.

## Step 2, lab ready, 2026-10-06: dry run on the laptop 10/10, store clean

`lab/gate2/run.py` is the Docker run (one fhirant, two clients, P1–P5 and
P0, the Gate 1 shaping and duty loop, a packet capture, the server's own dump
of every stored blob, and the canary scan over dump, store file and capture).
`lab/gate2/dry_run.sh` is the same pipeline on the laptop with no Docker and
no shaping. Its result, `results/dry-2026-10-06`:

| sent | received | one-way median | one-way max | store after the run | canary scan |
|---|---|---|---|---|---|
| 10 | 10 | 126 ms | 696 ms | 1 commit, 9 key packages, 0 messages, 0 welcomes | clean (exit 0); positive control with a planted canary: 2 hits, exit 1 |

The one-way time on the laptop is the wake-up round trip (ping, then
collect, then decrypt), not the network. The 696 ms maximum is the first
message, which also carried the welcome and the join.

Not run: the Docker profiles. A run creates two Docker networks; it waits for
Grey's go (GATE1.md).
