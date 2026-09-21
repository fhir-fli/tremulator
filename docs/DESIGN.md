# How tremulator is built

Six steps, walked through with Grey on 2026-09-21. The current choices behind
each are in [DECISIONS.md](DECISIONS.md); none of it is frozen.

## 1. Never write the crypto

Two things we do not write. The primitives, meaning the maths that encrypts a
block or signs a message. And the protocol state machine on top, meaning which
key is used for which message and when it is thrown away.

Not in Dart specifically, because Dart collects garbage, so a key in memory is
copied around and cannot be wiped, and the compiler may rewrite comparisons so
that a check's timing depends on the secret. Rust allows both to be controlled.

Binding: the Rust is compiled into the app and a generator writes the Dart
functions that call it. `openmls` on pub.dev already does this, MIT.

## 2. Keys: MLS, RFC 9420

Each device publishes a stock of key packages in advance: a version and cipher
suite, a public init key, and a leaf node carrying an encryption key and a
signature key, all signed by the device (RFC 9420 section 10). Private keys
never leave the phone. Packages are single use except one kept as a last
resort, so each device tops up its stock.

A conversation is a tree of keys. When someone joins or leaves, everyone
derives a new key. A consultant added mid-case cannot read what came before; a
removed phone cannot read anything after. The RFC covers groups of two
explicitly.

## 3. Identity, delivery, storage: ours to build

MLS specifies none of these.

- **Identity.** A roster binding each clinician to their signing key, kept by
  fhirant and signed by enrollers (D7).
- **Delivery.** fhirant holds each device's key package stock, holds messages
  for phones that are off, and passes call setup. It never sees plaintext. It
  does see who talks to whom, when, how often and how much, and from which IP
  address. Running it ourselves keeps that pattern in the deployment's hands.
- **Storage.** Each device keeps its own history. The server need not keep a
  message once it is collected, which makes a purge policy simple.

Key state is ordered: two servers delivering the same changes in different
orders leave devices unable to read each other. So each conversation has one
server that orders it. Which one is open (D4).

## 4. Media: WebRTC

The Flutter package is MIT. WebRTC encrypts the media itself, and two phones
that connect directly have no server between them.

The hole it leaves: each side normally proves its key by sending a fingerprint
through the signalling server, which a dishonest server could swap. We send the
fingerprints through the MLS channel instead.

When two phones cannot reach each other a relay sits between them. It sees
encrypted media and both IP addresses.

Bandwidth is where calls fail. Video degrades to audio rather than dropping the
call. The numbers come from the network profiles in SUCCESS.md, not from
estimates.

Ringing an app that is closed is a separate problem, still unsolved.

## 5. Bind each key to a real person

Enrollment: people with the enroller role add clinicians and their devices to
the roster, and can be in different places. The deployment sets how many
signatures that takes, down to one, including for protection cases (D7). Every
addition and every access to a restricted record is logged and visible.

Per conversation: both phones show the same short code, read aloud on the first
call. It works because colleagues recognise each other's voices. After that, a
changed key is announced loudly, never accepted quietly.

## 6. Someone outside has to look at it

The primitives are audited. Our use of them is not: whether a removed device
really loses access, whether the WebRTC fingerprints really travel through MLS,
what happens when a key package stock runs dry, whether the roster can be
tricked.

Before any review, the adversary harness in SUCCESS.md: dump the server's
database and capture the traffic, and prove nothing readable is in either.

Then review. What it costs, looked up 2026-09-21:

- **Paid.** The Open Source Technology Improvement Fund, which brokers audits
  between vetted firms, puts initial audits at **$30,000 to $200,000**,
  depending on complexity, with cryptography pushing it up. That is their
  published range, not a quote.
- **Free, if eligible.** The Open Technology Fund's Red Team Lab audits
  projects it funds, and projects it doesn't fund may apply if they are
  relevant to internet freedom. It reports more than 85 audits. Whether a
  clinical messaging tool for disaster and conflict settings qualifies is
  unknown until we ask. Its current funding status was not checked.
- **Free, informally.** Put the design in front of the MLS working group and
  the OpenMLS maintainers.
