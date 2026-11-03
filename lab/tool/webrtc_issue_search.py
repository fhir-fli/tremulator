"""Searches the WebRTC issue tracker (issues.webrtc.org) the way its own page
does: POST /action/issues/list with [.., [query, null, page size,
"start_index:N"]]. Writes one JSON line per hit, flushed, to OUT, with the
query, issue id, title and status code, and prints each query's count. Used
2026-11-02 to look for earlier reports of the audio hold that survives video
stopping (D17).

usage: python3 -I webrtc_issue_search.py OUT.jsonl QUERY..."""
import json
import sys
import urllib.request

URL = "https://issues.webrtc.org/action/issues/list"
PAGE = 50
CAP = 500


def search(query, start):
    body = json.dumps([None, None, None, None, None, None,
                       [query, None, PAGE, f"start_index:{start}"]]).encode()
    req = urllib.request.Request(URL, data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        t = r.read().decode()
    return json.loads(t[t.index("\n") + 1:])


def issues(node):
    """Each issue record: [null, id, [tracker, ?, ?, status, ?, title, ...]]."""
    if isinstance(node, list):
        if (len(node) > 2 and node[0] is None and isinstance(node[1], int)
                and node[1] > 1000 and isinstance(node[2], list)
                and len(node[2]) > 5 and isinstance(node[2][5], str)):
            yield node[1], node[2][5], node[2][3]
            return
        for x in node:
            yield from issues(x)


with open(sys.argv[1], "a") as out:
    for q in sys.argv[2:]:
        start, seen = 0, 0
        while True:
            got = list(issues(search(q, start)))
            for i, title, status in got:
                out.write(json.dumps({"query": q, "id": i, "title": title,
                                      "status": status}) + "\n")
                out.flush()
            seen += len(got)
            if len(got) < PAGE or seen >= CAP:
                break
            start += PAGE
        print(f"{seen:4d}{' (CAP: cut short)' if seen >= CAP else ''}  {q}",
              flush=True)
