# MLS test vectors

Copied unchanged from the MLS working group's interoperability repository,
`mlswg/mls-implementations`, directory `test-vectors/`, at commit
`2034fe72e0c805a683ba76165660c834f2a8142a` (2026-10-07). The format and
the checks each file asks for are in that repository's `test-vectors.md`.

Only the files `mls_vectors_test.dart` reads are here. All sixteen are run
against the openmls library itself by `lab/e2/openmls_kats.sh`.

| file | sha256 |
|---|---|
| deserialization.json | 1e394706e79f77df71454e5970f2aa736d4ab8b6c7e3219dd5609992388a953e |
| messages.json | b194abe1561995223482dbad51c180146920dc2f637e74d01e07a388308791fb |
| passive-client-handling-commit.json | b24949fdf857bf79d511f57504a8bdc7ce3247eb199684745e439c11b1a1da21 |
| passive-client-random.json | 0095d863e9d316872e237fc708debcd20ba2687ee905a3e831f97dd3e578d3c1 |
| passive-client-welcome.json | 92ebb04b67b1aca4290965ae363650921842ceebe275bd79a2733414078d849c |
| welcome.json | 06be9d5c99817ef2545e4b15b8e73fd9b604685a8e55b59ca168eda98e236502 |
