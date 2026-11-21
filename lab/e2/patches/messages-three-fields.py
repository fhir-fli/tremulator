"""Adds to openmls 0.9.0's messages.json known-answer test the three fields it
loads and never checks (re_init_proposal, external_init_proposal,
group_context_extensions_proposal): each decoded with the type openmls's
receiving path uses (messages/proposals_in.rs, ProposalIn) and re-encoded to
the same bytes, as test-vectors.md asks for every field. Each outcome is
written to RUN_DIR/fieldcheck.txt, one line per field per entry; the test
itself is not made to fail, so all 300 entries are seen.

    python3 -I patches/messages-three-fields.py RUN_DIR
"""
import sys

path = sys.argv[1] + "/openmls/src/group/tests_and_kats/kats/messages.rs"
src = open(path).read()
anchor = "    // Re-Init, External Init and App-Ack Proposals go here...\n"
assert src.count(anchor) == 1, "anchor not found once"
check = """
    for (name, tv_bytes, mine) in [
        ("ReInitProposal", &tv.re_init_proposal,
         ReInitProposal::tls_deserialize_exact(&tv.re_init_proposal).map(|p| p.tls_serialize_detached().unwrap())),
        ("ExternalInitProposal", &tv.external_init_proposal,
         ExternalInitProposal::tls_deserialize_exact(&tv.external_init_proposal).map(|p| p.tls_serialize_detached().unwrap())),
        ("GroupContextExtensionProposal", &tv.group_context_extensions_proposal,
         crate::messages::proposals_in::GroupContextExtensionProposalIn::tls_deserialize_exact(&tv.group_context_extensions_proposal).map(|p| p.tls_serialize_detached().unwrap())),
    ] {
        let outcome = match mine {
            Ok(mine) if &mine == tv_bytes => "ok".to_string(),
            Ok(_) => "re-encodes differently".to_string(),
            Err(e) => format!("does not decode: {e:?}"),
        };
        // One line per field per entry, appended and flushed as it happens,
        // to fieldcheck.txt at the tree's root (lab/e2/build/run-LABEL/).
        use std::io::Write as _;
        let mut out = std::fs::OpenOptions::new().create(true).append(true)
            .open(concat!(env!("CARGO_MANIFEST_DIR"), "/../fieldcheck.txt")).unwrap();
        writeln!(out, "{name} {outcome}").unwrap();
        out.flush().unwrap();
    }
"""
open(path, "w").write(src.replace(anchor, anchor + check))
print("patched", path, flush=True)
