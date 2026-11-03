"""Fetches issues from the WebRTC/Chromium issue tracker's JSON endpoint
(issues.webrtc.org/action/issues/<id>) and writes, per issue, its title and
every long text field (description and comments as the endpoint returns
them), flushed, to OUT. Companion to webrtc_issue_search.py.

usage: python3 -I webrtc_issue_read.py OUT.txt ID..."""
import json
import sys
import urllib.request


def texts(node, out):
    if isinstance(node, str):
        if len(node) > 40 and not node.startswith("<p>"):
            out.append(node)
    elif isinstance(node, list):
        for x in node:
            texts(x, out)


def numbers(node, out):
    """Epoch-second timestamps [seconds, nanos] anywhere in the record."""
    if isinstance(node, list):
        if (len(node) == 2 and isinstance(node[0], int)
                and 1_000_000_000 < node[0] < 2_000_000_000):
            out.append(node[0])
        for x in node:
            numbers(x, out)


with open(sys.argv[1], "a") as f:
    for i in sys.argv[2:]:
        with urllib.request.urlopen(
                f"https://issues.webrtc.org/action/issues/{i}", timeout=60) as r:
            t = r.read().decode()
        d = json.loads(t[t.index("\n") + 1:])
        found, stamps = [], []
        texts(d, found)
        numbers(d, stamps)
        f.write(f"===== {i}  stamps {min(stamps) if stamps else '-'}"
                f"..{max(stamps) if stamps else '-'}\n")
        for s in found:
            f.write(s + "\n---\n")
        f.flush()
        print(i, len(found), flush=True)
