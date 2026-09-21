#!/usr/bin/env python3
"""Toy relay server for the adversary-harness mutation test. It is NOT
tremulator: it exists so the scanner can be shown to catch known defects.
Stores whatever it receives in SQLite, logs request headers, serves fetches.
DEFECT is read from the environment by the client, not here; the server is
honest and dumb, like the real delivery service should be."""
import json, os, sqlite3, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
DB = os.environ.get("TOY_DB", "/work/server.db")
LOG = open(os.environ.get("TOY_LOG", "/work/server.log"), "a")
db = sqlite3.connect(DB, check_same_thread=False)
db.execute("create table if not exists msg (id integer primary key, recipient text, payload text)")
db.commit()
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def _body(self):
        n = int(self.headers.get("Content-Length", "0")); return self.rfile.read(n)
    def do_POST(self):
        LOG.write(json.dumps({"path": self.path, "headers": dict(self.headers)}) + "\n"); LOG.flush()
        if self.path == "/send":
            m = json.loads(self._body())
            db.execute("insert into msg (recipient, payload) values (?, ?)", (m["to"], json.dumps(m)))
            db.commit(); self.send_response(200); self.end_headers(); self.wfile.write(b"ok")
        else:
            self.send_response(404); self.end_headers()
    def do_GET(self):
        if self.path.startswith("/fetch/"):
            who = self.path.split("/")[-1]
            rows = [json.loads(r[0]) for r in db.execute("select payload from msg where recipient=?", (who,))]
            b = json.dumps(rows).encode()
            self.send_response(200); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
        else:
            self.send_response(404); self.end_headers()
HTTPServer(("0.0.0.0", 8080), H).serve_forever()
