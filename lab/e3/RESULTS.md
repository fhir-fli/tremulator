# E3: planted defects (2026-11-21)

Plan: `docs/GATE2-CALLS-PLAN.md`, the E3 plan under the endpoints table,
written and committed (f776576) before anything was planted. Each defect is a
patch in `plants/`, applied by `plant.sh` to a throwaway copy of HEAD (a git
worktree); the same tests run on that copy with nothing planted
(`plant.sh none`) for the green side. GUI tests run only through
`lab/tool/call_tests.sh` (virtual screen, silent sound).

| | Defect planted | Test | Planted | Not planted |
|---|---|---|---|---|
| a | our check that a later setup keeps the first certificate fingerprint, off (`a-fingerprint-check-off`) | the three fingerprint tests in `calls_test.dart` | 2 of 3 red: both restart-fingerprint tests (30 s timeouts); the first-setup test stayed green, as predicted, since WebRTC itself refuses the wrong certificate (RFC 8122 section 6.2) | 3 of 3 green |
| b | call setup sent as plain text (`b-call-setup-unencrypted`) | `client_test` "call setup arrives labelled as a call"; the lab's fingerprint hunt on the server | client test red (`b-planted-client.log`); lab `e3b-planted2`: Alice's fingerprint found 94 times, all in the server's packet capture | client suite 15 of 15 green; lab `e3b-main`: both fingerprints hunted, 0 found on the server, 2 in the phones' own logs (the control) |
| c, e | call setup that does not decrypt read as plain text (`ce-undecryptable-call-read-as-text`) | `dishonest_server_test.dart`, 6 tests | 6 of 6 red | 6 of 6 green |
| d | the relay report switched off (`d-relay-silence`) | two new relay tests in `calls_test.dart` | the refusing-relay test red (`relayUnavailable` false); the no-relay control green | 2 of 2 green; calls suite 20 of 20 |

## (c) and (e): what refused each swap

The six swaps a dishonest server or an outsider could make, each reported
`undecryptable` by Bob's phone with nothing reaching the call code
(`results/ce-main.log`, the library's own error text):

- its own offer in plain text: "not an MLS message" (fhirant also refuses to
  store one, below);
- a replay of a call message Bob already had: "The requested secret was
  deleted to preserve forward secrecy";
- a message from a conversation Bob is not in: "No group found in storage";
- one byte changed: "An error occurred during AEAD decryption";
- an outsider's message from its own conversation: "No group found";
- an outsider's message with Alice and Bob's group id written into the
  header: "AEAD decryption". The group id is in the data the encryption
  authenticates (RFC 9420 section 6.3.1, PrivateContentAAD).

Not covered, noted: the sender the mailbox reports (`Envelope.from`, the
server's word) is not compared with the sender inside the encrypted
message. Nothing uses it to decide anything today (searched every `lib/`
for `.from`, 2026-11-21: only passed on and logged). It will matter once a
conversation has more than two members, or a screen shows who is calling.

## (d): the new code

A phone that gathers its addresses with a relay configured and gets no
relay address now says so (`Call.relayUnavailable`, event
`relay-unavailable`, and on `setup-failed` / `setup-deadline`). It cannot
say which of the two causes it was, wrong password or relay unreachable:
the plugin offers no relay-error event (webrtc_interface 1.5.1, searched
for `IceCandidateError` and `icecandidateerror`: no match). The test's fake
relay answers every allocation 401, as RFC 8656 section 7.3 has a server do
with wrong credentials, and counts that the phones asked again with
credentials.

## (b): the lab run, and the blind spot it found

First run (`results/e3b-planted`): the server's dump and capture were
scanned and showed 0 hits, but the hunt had 0 fingerprints to look for
(`fingerprints: 0` in the summary). It took them only from a connected
call's statistics, and this call never connected. So the scan was blind,
not clean. Fixed in 97ad443: each phone logs its own fingerprints when it
gathers, and a scan with nothing to hunt reports `fingerprint_scan_blind`.

The same run showed fhirant refusing the plain-text setup: every upload was
answered 422, "The file at Communication.payload.content.data is not
message/mls" (Alice: 45 failed sends, `e3b-planted/none/alice.jsonl`). So
the server never stored it; the 422 means the server received it.

Second run, after the fix (`results/e3b-planted2`, `e3b-main`): planted,
1 fingerprint to hunt (Alice's; Bob never got the offer, so never answered),
94 hits, every one in `traffic.pcap` (the request bodies the server
refused); not planted, 2 fingerprints, 0 hits, control 2.

## (d) in the lab, with the real relay (coturn)

Direct route between the phones blocked (`none-blocked`), so the call can
only go through the relay.

- Wrong password (`e3d-wrong`): coturn logged "user lab credentials are
  incorrect" and answered 401 to both phones. Each phone reported the
  relay unavailable 0.1 s into gathering (0 relay addresses). The call never
  connected; Alice ended it at the 90 s setup deadline as failed, with
  `relay-unavailable: true` on the deadline report; Bob ended on her
  hang-up.
- Right password (`e3d-right`, the control): Alice 3 relay addresses, Bob 1,
  no warning, connected through the relay in 0.45 s, held 30 s.

## Open: a false warning on an open network

In `e3b-main` (profile `none`, direct route open, right password) Bob, the
answering phone, reported the relay unavailable: his gathering finished in
11 ms with no relay address, while Alice got 3 in 104 ms. The call itself
connected directly and was fine. Earlier runs show the same timing for the
answering phone on `none` (calls51ba 15 ms, calls51bb 3 ms) against about
460 ms on `P2-blocked`, where he does get one. Cause not measured. Each
gathering state and each address are now logged with their times, and a run
on `none` will say. Until then the warning can be wrong on the answering
side when the network is open.
