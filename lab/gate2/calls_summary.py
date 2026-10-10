"""One line per phone from a calls run's JSON-lines logs: connected or not,
the route, connect time from call-started to connected, and the last video
and audio counters the receiver saw. Usage: calls_summary.py LOG [LOG...]"""
import json
import sys
from datetime import datetime


def t(e):
    return datetime.fromisoformat(e["t"].replace("Z", "+00:00"))


for path in sys.argv[1:]:
    events = [json.loads(l) for l in open(path) if l.strip()]
    first = {}
    for e in events:
        first.setdefault(e["event"], e)
    start = first.get("call-started") or first.get("signal-received")
    conn = first.get("connected")
    last_in = {}
    for e in events:
        if e["event"] == "stats":
            for r in e["reports"]:
                if r.get("type") == "inbound-rtp":
                    last_in[r.get("kind")] = r
    v, a = last_in.get("video", {}), last_in.get("audio", {})
    print(json.dumps({
        "log": path,
        "connected": conn is not None,
        "route": conn and conn.get("route"),
        "connect-ms": int((t(conn) - t(start)).total_seconds() * 1000) if conn and start else None,
        "video-frames-decoded": v.get("framesDecoded"),
        "video-freeze-count": v.get("freezeCount"),
        "video-total-freezes-s": v.get("totalFreezesDuration"),
        "video-size": [v.get("frameWidth"), v.get("frameHeight")] if v else None,
        "audio-packets": a.get("packetsReceived"),
        "failed": [e for e in events if e["event"] in ("run-failed", "start-failed")][:1],
        "ended": first.get("call-ended", {}).get("why"),
    }), flush=True)
