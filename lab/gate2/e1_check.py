"""Run from lab/gate2. E1, a browser calls the app (docs/GATE2-CALLS-PLAN.md):
Chrome (the app's web build, Chrome for Testing 158.0.8127.36) and the Linux
app connect, each shows and plays the other's test picture and clicks, and
the identity check holds. calls_e1.sh makes the runs. Method and pass rule,
fixed before the sweep was read (2026-11-19):

A call run passes when, from the run's own summary line (calls.py):
- both apps exit 0 and both logged `connected`;
- Bob decoded video frames (> 0) and his screen recording froze for less
  than half the call (Gate 1's freezedetect; the first ~12 s before video
  starts are frozen in every call, calls43/45);
- Bob heard every click Alice sent but at most one (clicks_heard >=
  clicks_sent - 1), each timed by voice_delay.py;
- 0 certificate fingerprints found on the server, with the positive control
  (Alice's own log) finding them.
Chrome as Bob tests Chrome receiving and playing; Chrome as Alice tests
Chrome capturing the screen and the microphone and sending. The native call
in the same sweep is the reference for the numbers, not part of the rule.

A planted run (`--plant-changed-fingerprint`, the phone that reads a
changed fingerprint is the browser) passes when neither phone logged
`connected`, and the planted phone logged `setup-failed` with why
`handshake` (its DTLS transport failed: W3C WebRTC 1.0 RTCDtlsTransportState
"failed", "failure to validate the remote fingerprint").

One line per run, then one verdict line. usage:
python3 e1_check.py OUT.jsonl LABEL..."""
import json
import os
import sys


def events(path):
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path):
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


rows = []
with open(sys.argv[1], "a") as out:
    for label in sys.argv[2:]:
        for line in open(os.path.join("results", f"{label}.jsonl")):
            r = json.loads(line)
            if "profile" not in r or "alice_exit" not in r and "placed" not in r:
                continue
            d = os.path.join("results", label, r["profile"])
            logs = {w: events(os.path.join(d, f"{w}.jsonl")) for w in ("alice", "bob")}
            connected = {w: any(e.get("event") == "connected" for e in logs[w]) for w in logs}
            planted = r.get("planted_changed_fingerprint")
            row = {"check": "e1", "run": label, "profile": r["profile"],
                   "browser": r.get("browser"), "planted": planted,
                   "exits": [r.get("alice_exit"), r.get("bob_exit")], "connected": connected}
            if planted:
                failed = [e for e in logs[planted] if e.get("event") == "setup-failed"]
                row["setup_failed"] = failed[:1]
                row["pass"] = (not any(connected.values())
                               and any(e.get("why") == "handshake" for e in failed))
            else:
                bob = r.get("bob") or {}
                v = r.get("voice") or {}
                rec = r.get("recording_bob") or {}
                window = rec.get("call_window_s") or [0, 0]
                call_s = window[1] - window[0]
                row.update({
                    "route": bob.get("route"),
                    "bob_frames_decoded": bob.get("video-frames-decoded"),
                    "bob_frozen_s": rec.get("frozen_s"), "call_s": round(call_s, 1),
                    "clicks": [v.get("clicks_heard"), v.get("clicks_sent")],
                    "voice_median_ms": v.get("delay_median_ms"),
                    "voice_max_ms": v.get("delay_max_ms"),
                    "fingerprint_hits": [r.get("fingerprint_hits"), r.get("fingerprint_control_hits")],
                })
                row["pass"] = bool(
                    r.get("alice_exit") == "0" and r.get("bob_exit") == "0"
                    and all(connected.values())
                    and (bob.get("video-frames-decoded") or 0) > 0
                    and rec.get("frozen_s") is not None and call_s > 0
                    and rec["frozen_s"] < call_s / 2
                    and v.get("clicks_sent") and v.get("clicks_heard") is not None
                    and v["clicks_heard"] >= v["clicks_sent"] - 1
                    and r.get("fingerprint_hits") == 0
                    and (r.get("fingerprint_control_hits") or 0) > 0)
            rows.append(row)
            out.write(json.dumps(row) + "\n")
            out.flush()
            print(json.dumps(row), flush=True)
    judged = [x for x in rows if x["browser"]]
    verdict = {"check": "e1-verdict", "runs": len(judged),
               "passed": sum(x["pass"] for x in judged),
               "e1_pass": bool(judged) and all(x["pass"] for x in judged)}
    out.write(json.dumps(verdict) + "\n")
    out.flush()
    print(json.dumps(verdict), flush=True)
