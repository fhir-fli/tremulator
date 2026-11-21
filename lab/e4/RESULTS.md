# E4: the relay sees only encrypted media (2026-11-21)

Plan: `docs/GATE2-CALLS-PLAN.md`, E4 plan, committed before any run. Run:
`bash lab/e4/run.sh` (two 60 s calls, `none-blocked`, so every packet goes
through the relay; `calls.py --relay-capture`). Scan: `relay_scan.py`.

Change from the plan, said to Grey before the runs: both calls have Alice
calling; instead of swapping the caller, the click track plays into both
phones' microphones, so both directions carry clicks.

The scan, first under known conditions (`self_check.py`,
`results/self_check.jsonl`): the click track as plain Opus RTP, 9 of 9
clicks in order; the same inside TURN ChannelData, 9 of 9; payloads
replaced by random bytes, 0.

| | e4a | e4b |
|---|---|---|
| clicks Bob heard (the clicks were in the call) | 5 of 5, median 116 ms | 5 of 5, median 70 ms |
| control at the relay (plain Opus RTP, same capture) | 9 of 9, in order | 9 of 9, in order |
| clicks found in the call's streams at the relay | 0 (2 sound streams, 5,904 and 6,014 packets; 1 video, 19,680) | 0 (6,052, 6,142; 18,644) |
| fingerprints found in the relay's capture and log | 0 of 2 | 0 of 2 |
| DTLS the phones used | 1.3 (ServerHello supported_versions 0xfefc) | 1.3 |
| certificates readable at the relay | 0 | 0 |

E4 passes: what the relay carried decodes to no click, the same scan finds
every click when the media is plain, and neither phone's fingerprint
crosses it.

Certificates: with DTLS 1.3 the certificates travel encrypted (RFC 9147),
so the relay cannot tell which phones are talking from them. Not checked:
the certificate reader itself on a DTLS 1.2 handshake (none occurred), so
"0 readable" rests on the version the ServerHello chose, not on the reader
having found certificates before.

Not checked: that Bob's clicks reached Alice (only Bob's speaker is
recorded); his `paplay` ran without error. The video is not scanned for the
test picture (no detector for it in a capture).

Found on the way: the temporary folder's space ran out twice during the
runs (another session's 16 GB Dart test build in /tmp); no run was lost.
