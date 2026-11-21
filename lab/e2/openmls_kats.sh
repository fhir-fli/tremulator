#!/usr/bin/env bash
# E2, the library part: the MLS working group's published test vectors run
# through openmls's own known-answer tests, at the exact openmls the app
# ships (openmls_dart 3.2.1 links openmls git tag openmls-v0.9.0, commit
# 3a3e35de, its rust/Cargo.lock). openmls keeps its own copies of the
# vectors, and 6 of the 16 differ from the working group's current files,
# so the current files are put in their place before the tests are built.
#
#     [PATCH=name.py] bash lab/e2/openmls_kats.sh LABEL [VECTOR_DIR]
#
# VECTOR_DIR defaults to the official files at VEC_COMMIT, fetched once and
# checked against the sha256 list below; another directory (a damaged copy,
# to see a test go red) is used as given. Rust runs in a pinned Docker image
# (no Rust on the host). Output: lab/e2/results/LABEL.log (cargo's own
# output) and LABEL.summary (one line per test: name, ok/FAILED).
set -euo pipefail
label=$1
HERE=$(cd "$(dirname "$0")" && pwd)
BUILD="$HERE/build"
OUT="$HERE/results"
mkdir -p "$BUILD" "$OUT"

OPENMLS_COMMIT=3a3e35de3feeca8f6605143c464d5452ae584d43
OPENMLS_TGZ_SHA256=e5dce825ec6fad89711729cc8af295e6ef1c6a26dd16d74c3a8cc685b76645fe
VEC_COMMIT=2034fe72e0c805a683ba76165660c834f2a8142a  # mlswg/mls-implementations, 2026-10-07
IMAGE=rust@sha256:e187887ec511b3d93e45c0231d2f0fd59f1347526c58aa86343aa83c74f3e1a9  # rust:1.91.0-bookworm
# sha256 of each file at VEC_COMMIT, as downloaded 2026-11-20.
VEC_SHA256="
crypto-basics.json 17cfcf89af9f51d0f2aa7af77f6f9ec99376a039214b6d42a6f11646b83e8c29
deserialization.json 1e394706e79f77df71454e5970f2aa736d4ab8b6c7e3219dd5609992388a953e
key-schedule.json 05aa9a68bd2538ace72d8c53375984cc728ef62220ebf314df675708546d97a7
message-protection.json f7c1ae62ce63c3003e526d539c99f2b1444f65ee0a487d3a5667d46867526c45
messages.json b194abe1561995223482dbad51c180146920dc2f637e74d01e07a388308791fb
passive-client-handling-commit.json b24949fdf857bf79d511f57504a8bdc7ce3247eb199684745e439c11b1a1da21
passive-client-random.json 0095d863e9d316872e237fc708debcd20ba2687ee905a3e831f97dd3e578d3c1
passive-client-welcome.json 92ebb04b67b1aca4290965ae363650921842ceebe275bd79a2733414078d849c
psk_secret.json 2b534969dba0b65a04b7d790496af5c0ccdb472b3fc4ca25c8c82df3e8523784
secret-tree.json 08f92e6272452e2c832e32d38e16cf0c4aa28967e47d3842c60bc354c6b67a94
transcript-hashes.json 58046b58fbd98519b4e60953a105f550e4b427e2b140ea67dedcb751260eecb8
tree-math.json 27f04891f56106593b74b674445f01b845e173953770c084deb2f8cf5592e2fc
tree-operations.json 9a25f8720714d1256ba2dad8d83a660ba0bae0d33ed15c682b9d74a5d67aad0a
tree-validation.json b66a432d93b520623f0640835ed43b9dfc95e116b8be081d81581d7c11e67a37
treekem.json d8bbdf78394797f21db7476fd286af6830ebcb18d2e3b2c839fecd4eb11056f8
welcome.json 06be9d5c99817ef2545e4b15b8e73fd9b604685a8e55b59ca168eda98e236502
"

tgz="$BUILD/openmls-${OPENMLS_COMMIT:0:8}.tar.gz"
if [ ! -f "$tgz" ]; then
  curl -fsSL -o "$tgz.part" "https://codeload.github.com/openmls/openmls/tar.gz/$OPENMLS_COMMIT"
  mv "$tgz.part" "$tgz"
fi
echo "$OPENMLS_TGZ_SHA256  $tgz" | sha256sum -c --quiet

official="$BUILD/vectors-${VEC_COMMIT:0:8}"
if [ ! -d "$official" ]; then
  mkdir -p "$official.part"
  for f in $(awk '{print $1}' <<< "$VEC_SHA256"); do
    curl -fsSL -o "$official.part/$f" \
      "https://raw.githubusercontent.com/mlswg/mls-implementations/$VEC_COMMIT/test-vectors/$f"
  done
  mv "$official.part" "$official"
fi
(cd "$official" && awk 'NF==2{print $2"  "$1}' <<< "$VEC_SHA256" | sha256sum -c --quiet)
vectors=$(cd "${2:-$official}" && pwd)
count=$(ls "$vectors"/*.json | wc -l)
[ "$count" -eq 16 ] || { echo "expected 16 vector files in $vectors, found $count" >&2; exit 1; }

run="$BUILD/run-$label"
rm -rf "$run"; mkdir -p "$run"
tar -xzf "$tgz" -C "$run" --strip-components=1
cp "$vectors"/*.json "$run/openmls/test_vectors/"
# The files the tests read, against what was meant to go in.
# (A plain loop: errexit does not fire inside an && list, so a failed cd
# there skipped this check silently on 2026-11-20.)
for f in "$vectors"/*.json; do
  if ! cmp -s "$f" "$run/openmls/test_vectors/$(basename "$f")"; then
    echo "not copied: $f" >&2; exit 1
  fi
done

# PATCH (optional): a script from patches/ run on the extracted tree, to add
# a check openmls's own test leaves out.
if [ -n "${PATCH:-}" ]; then python3 -I "$HERE/patches/$PATCH" "$run"; fi

# Every test that reads a working-group file. read_test_vectors_encryption
# reads openmls's own kat_encryption_openmls.json and is run too, reported
# apart. The tests are named in the summary; a run of other than 15 tests
# fails (below).
mkdir -p "$BUILD/cargo-home" "$BUILD/target"
code=0
docker run --rm --network host \
  -u "$(id -u):$(id -g)" \
  -e CARGO_HOME=/cargo -e CARGO_TARGET_DIR=/target \
  -v "$BUILD/cargo-home:/cargo" -v "$BUILD/target:/target" -v "$run:/src" \
  -w /src "$IMAGE" \
  cargo test --locked -p openmls --features test-utils --lib -- \
    read_test_vectors test_read_vectors > "$OUT/$label.log" 2>&1 || code=$?
grep -E '^test .* \.\.\. (ok|FAILED|ignored)' "$OUT/$label.log" | sed -E 's/^test //; s/ \.\.\. / /' > "$OUT/$label.summary" || true
echo "$label: cargo exit $code; $(grep -c ' ok$' "$OUT/$label.summary") ok, $(grep -c ' FAILED$' "$OUT/$label.summary") failed"
# 14 tests read the 16 working-group files, plus read_test_vectors_encryption
# on openmls's own file: 15 (official run 2026-11-20). Fewer means the filter
# or the source changed, and a green run would cover less than it says.
ran=$(wc -l < "$OUT/$label.summary")
[ "$ran" -eq 15 ] || { echo "$label: $ran tests ran, expected 15" >&2; [ "$code" -ne 0 ] || code=97; }
exit "$code"
