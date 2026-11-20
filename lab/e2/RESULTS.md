# E2: MLS known answers (2026-11-20)

Vectors: mlswg/mls-implementations `test-vectors/`, commit `2034fe72`
(2026-10-07), all 16 files, sha256 in `openmls_kats.sh`. The checks each
file asks for: that repository's `test-vectors.md`.

## Through tremulator_keys (Dart)

`packages/tremulator_keys/test/mls_vectors_test.dart`, 10 tests, all pass
(whole package 22/22, analyze clean). It runs the files our own code can
read: 14 length headers; 300 key packages unwrapped and wrapped back; 300
GroupInfos read to the end; 1,200 public and private messages from
messages.json plus 2,008 from the passive-client files, each giving the
group, epoch and kind its header holds (checked against a second reader
in the test); every welcome refused as a key package. Each check was seen
red: a damaged length, a GroupInfo with a byte added, a welcome relabelled
as a key package, unwrap dropping a byte, a proposal reported as a commit,
the epoch off by one.

Not covered by the official files: removing our "shortest length encoding"
check (RFC 9420 section 2.1.2, MUST) left the vector test green; none of
the 14 headers is a longer-than-needed encoding. Our own
`mls_message_test.dart` covers it.

Not reachable from Dart: the library makes and keeps its own private
keys and offers no way to load given ones, so joining from welcome.json
and following the passive-client groups can only run on the library side.

## Through openmls 0.9.0 itself (the library the app ships)

`bash lab/e2/openmls_kats.sh LABEL`: openmls's own 14 known-answer tests
that read the 16 files, with the working group's current files in place
of openmls's copies (6 of its copies differ), in Docker rust:1.91.0.
Result `results/official2.*`: 15 of 15 pass (the 15th reads openmls's own
encryption file). Damaged copies (`damage.py`, one known answer changed in
a suite-1 entry per file): every one of the 14 tests failed
(`results/damaged-*`).

Cipher suites: the crypto backend the app uses supports suites 1, 2 and 3;
every test skips suites 4-7 without saying so. Checked entries / all:
crypto-basics 3/7, key-schedule 3/7, message-protection 3/7,
transcript-hashes 3/7, welcome 3/7, secret-tree 9/21, psk_secret 33/77,
tree-validation 42/98, treekem 33/77, passive welcome 24/56, passive
handling-commit 39/91, passive random 1/1, tree-operations 5/5 (all suite
1). The app uses suite 1, which every file covers.

Checks `test-vectors.md` asks for that openmls's tests do not make (read
in the source at commit 3a3e35de; the first three confirmed by hand):

1. message-protection: "protecting [the application message] as a
   PublicMessage fails" is never tried.
2. messages: 3 of 14 fields (`re_init_proposal`, `external_init_proposal`,
   `group_context_extensions_proposal`) are loaded but never decoded or
   re-encoded ("Re-Init, External Init and App-Ack Proposals go here...",
   messages.rs:488).
3. passive-client: the three private keys are not checked against the key
   package (`_signature_priv` unused, passive_client.rs:243); they are
   only used, so a mismatch would show as a failed join.
4. treekem: the leaf's own encryption and signature private keys are not
   checked against the tree; the fresh UpdatePath round trip runs against
   a group context whose tree hash is not updated (TODO #1279, lines 188,
   250, 265).
5. tree-math: the root's empty parent and sibling are not asserted.

The leaf-node lifetime check is switched off for the passive-client
files (the vectors' key packages have expired).
