"""Damaged copies of the official MLS vectors, to see each openmls known-answer
test go red once (a test is not evidence until it has failed).

    python3 -I lab/e2/damage.py OFFICIAL_DIR OUT_DIR SET

One known answer is changed in the first cipher-suite-1 entry (suite 1 is
the app's) of each file in SET; the other files are copied unchanged.
passive_client.rs reads its three files in one test and stops at the first
failure, so each passive file is damaged in a set of its own:
  main     the 13 non-passive files and passive-client-welcome.json
  random   passive-client-random.json only
  handling passive-client-handling-commit.json only
Each change is printed, flushed, as it is made.
"""
import json
import os
import shutil
import sys


def flip(h):
    """The hex string with its last digit changed."""
    return h[:-1] + ("0" if h[-1] != "0" else "1")


def suite1(entries):
    return next(e for e in entries if e.get("cipher_suite") == 1)


# file -> (description, function changing the parsed file in place)
DAMAGE = {
    "crypto-basics.json": ("expand_with_label.out", lambda d: suite1(d)["expand_with_label"].update(out=flip(suite1(d)["expand_with_label"]["out"]))),
    "deserialization.json": ("entry 0 length + 1", lambda d: d[0].update(length=d[0]["length"] + 1)),
    "key-schedule.json": ("epochs[0].joiner_secret", lambda d: suite1(d)["epochs"][0].update(joiner_secret=flip(suite1(d)["epochs"][0]["joiner_secret"]))),
    "message-protection.json": ("application_priv last byte", lambda d: suite1(d).update(application_priv=flip(suite1(d)["application_priv"]))),
    "messages.json": ("entry 0 mls_welcome cut by one byte", lambda d: d[0].update(mls_welcome=d[0]["mls_welcome"][:-2])),
    "psk_secret.json": ("psk_secret", lambda d: suite1(d).update(psk_secret=flip(suite1(d)["psk_secret"]))),
    "secret-tree.json": ("leaves[0][0].application_key", lambda d: suite1(d)["leaves"][0][0].update(application_key=flip(suite1(d)["leaves"][0][0]["application_key"]))),
    "transcript-hashes.json": ("confirmed_transcript_hash_after", lambda d: suite1(d).update(confirmed_transcript_hash_after=flip(suite1(d)["confirmed_transcript_hash_after"]))),
    "tree-math.json": ("entry 3 root + 1", lambda d: d[3].update(root=d[3]["root"] + 1)),
    "tree-operations.json": ("tree_hash_after", lambda d: suite1(d).update(tree_hash_after=flip(suite1(d)["tree_hash_after"]))),
    "tree-validation.json": ("tree_hashes[0]", lambda d: suite1(d)["tree_hashes"].__setitem__(0, flip(suite1(d)["tree_hashes"][0]))),
    "treekem.json": ("update_paths[0].commit_secret", lambda d: suite1(d)["update_paths"][0].update(commit_secret=flip(suite1(d)["update_paths"][0]["commit_secret"]))),
    "welcome.json": ("signer_pub", lambda d: suite1(d).update(signer_pub=flip(suite1(d)["signer_pub"]))),
    "passive-client-welcome.json": ("initial_epoch_authenticator", lambda d: suite1(d).update(initial_epoch_authenticator=flip(suite1(d)["initial_epoch_authenticator"]))),
    "passive-client-random.json": ("epochs[0].epoch_authenticator", lambda d: suite1(d)["epochs"][0].update(epoch_authenticator=flip(suite1(d)["epochs"][0]["epoch_authenticator"]))),
    "passive-client-handling-commit.json": ("epochs[0].epoch_authenticator", lambda d: suite1(d)["epochs"][0].update(epoch_authenticator=flip(suite1(d)["epochs"][0]["epoch_authenticator"]))),
}
SETS = {
    "main": [f for f in DAMAGE if f not in ("passive-client-random.json", "passive-client-handling-commit.json")],
    "random": ["passive-client-random.json"],
    "handling": ["passive-client-handling-commit.json"],
}


def main():
    src, out, which = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    names = sorted(f for f in os.listdir(src) if f.endswith(".json"))
    assert sorted(DAMAGE) == names, (sorted(DAMAGE), names)
    for name in names:
        if name not in SETS[which]:
            shutil.copy(os.path.join(src, name), os.path.join(out, name))
            continue
        with open(os.path.join(src, name)) as f:
            data = json.load(f)
        what, change = DAMAGE[name]
        change(data)
        with open(os.path.join(out, name), "w") as f:
            json.dump(data, f)
        print(f"{name}: {what}", flush=True)


if __name__ == "__main__":
    main()
