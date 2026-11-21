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
the tests skip suites 4-7 without saying so (tree-operations has no such check; all its entries are suite 1). Checked entries / all:
crypto-basics 3/7, key-schedule 3/7, message-protection 3/7,
transcript-hashes 3/7, welcome 3/7, secret-tree 9/21, psk_secret 33/77,
tree-validation 42/98, treekem 33/77, passive welcome 24/56, passive
handling-commit 39/91, passive random 1/1, tree-operations 5/5 (all suite
1). The app uses suite 1, which every file covers.

Checks `test-vectors.md` asks for that openmls's vector tests do not make.
Each re-read by hand in the 0.9.0 source on 2026-11-20 (Grey asked for a
recheck), and in openmls `main` at ba267737 (2026-11-18): all still there.

1. messages: 3 of the 14 fields (`re_init_proposal`,
   `external_init_proposal`, `group_context_extensions_proposal`) are
   loaded and never decoded or re-encoded ("Re-Init, External Init and
   App-Ack Proposals go here...", messages.rs:488; main:495). The other 11
   fields are read and compared. No open issue found (searched the
   repository's issues for the field names and for "test vectors"; that
   search does return older test-vector issues, e.g. #326, #490).
   Measured 2026-11-21 (`PATCH=messages-three-fields.py bash
   openmls_kats.sh fields-official`, outcomes in
   `results/fields-official.fieldcheck.txt`): ExternalInit 300/300 and
   GroupContextExtensions 300/300 decode and re-encode exactly; ReInit
   0/300 decode. Every official ReInit carries one extension, type 2
   (ratchet_tree; `reinit_extensions.py`, `results/reinit-extensions.txt`:
   no duplicates in any entry). RFC 9420 section 17.3 registers
   ratchet_tree for GroupInfo only, and section 11.2 makes ReInit's
   extensions the new group's GroupContext extensions; openmls allows only
   required_capabilities, external_senders and unknown types there
   (`is_valid_in_group_context`, extensions/mod.rs:208; same on main), so
   it refuses, but reports "Found duplicate extensions" (mod.rs:409; main
   :442), which is false: its decoder maps every refusal to that message.
   Whether the sample or openmls is right is not settled here: the
   registry column says where an extension "may appear", with no MUST.
   Each added check was seen red on a copy with that field cut by a byte
   (`cut_field.py`, `results/fields-cut-*`).
2. passive-client: the given private keys are not checked against the key
   package's public keys, the vector's first check
   (`_signature_priv` unused, passive_client.rs:243; `init_priv` and
   `encryption_priv` stored without comparison). A wrong `init_priv` would
   still show, as a failed join; a wrong `signature_priv` would not, since
   the passive client never signs.
3. message-protection: the vector test does not try protecting the
   application message as a PublicMessage. openmls does refuse it
   (`ValidationError::UnencryptedApplicationMessage`, framing/validation.rs:237)
   and tests that elsewhere (group/tests_and_kats/tests/framing_validation.rs:417),
   so this is a gap in the vector test only.
4. treekem: the leaf's own private keys are paired with the tree's public
   keys without a check, and the second half runs on a group context whose
   tree hash is not updated. Already tracked by openmls: issue #1279
   ("Tracking missing interop features", open since 2023-02-16, item
   "Resolve TODOs in TreeKEM").
5. tree-math: the root's empty parent and sibling are skipped, not
   asserted. Trivial: every official tree has them empty.

openmls's own copies of 6 of the 16 files differ from the working group's
current ones; with the current ones in place all 15 tests pass.

The leaf-node lifetime check is switched off for the passive-client
files (the vectors' key packages have expired).
