#!/usr/bin/env python3
"""The browser phone's lab helper (E1), behind nginx on the page's own
origin at /lab/. The page cannot write files, so it posts here:

- POST /lab/log: one JSON line, appended to LOG and flushed;
- GET /lab/stop: 200 once the stop-sign file STOP exists, else 404;
- POST /lab/exit: the run's exit code, written to EXIT.

usage: lab_helper.py PORT LOG STOP EXIT"""
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT, LOG, STOP, EXIT = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
LOCK = threading.Lock()


class Helper(BaseHTTPRequestHandler):
    def _body(self):
        return self.rfile.read(int(self.headers.get("Content-Length", "0"))).decode()

    def _reply(self, code):
        self.send_response(code)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_POST(self):
        if self.path == "/lab/log":
            line = self._body().strip()
            with LOCK, open(LOG, "a") as f:
                f.write(line + "\n")
                f.flush()
            self._reply(204)
        elif self.path == "/lab/exit":
            code = self._body().strip()
            with open(EXIT + ".tmp", "w") as f:
                f.write(code + "\n")
            os.replace(EXIT + ".tmp", EXIT)
            self._reply(204)
        else:
            self._reply(404)

    def do_GET(self):
        if self.path == "/lab/stop":
            self._reply(200 if os.path.exists(STOP) else 404)
        else:
            self._reply(404)

    def log_message(self, *args):
        pass


ThreadingHTTPServer(("127.0.0.1", PORT), Helper).serve_forever()
