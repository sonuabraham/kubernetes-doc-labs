#!/usr/bin/env python3
"""NOT from the docs: the "service under development", running on YOUR machine (not in the cluster).
Listens on 0.0.0.0:$PORT (default 18765) and answers like the in-cluster version, plus what it can see of the cluster."""
import os, socket
from http.server import BaseHTTPRequestHandler, HTTPServer
VERSION = os.environ.get("VERSION", "local-dev-1")
PORT = int(os.environ.get("PORT", "18765"))
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"hello from {VERSION} on {socket.gethostname()} (request from {self.client_address[0]})\n"
        self.send_response(200); self.end_headers(); self.wfile.write(body.encode())
    def log_message(self, fmt, *a): print("local app:", fmt % a, flush=True)
HTTPServer(("0.0.0.0", PORT), H).serve_forever()
